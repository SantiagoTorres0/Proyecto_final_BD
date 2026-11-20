-- =============================================================================
-- normalizacion.sql: migra la base del proyecto de biblioteca del
-- esquema anterior al esquema normalizado descrito y justificado en normalizacion.md
-- Evan David Arregocés Delgado - 202517690
-- Santiago Torres Martinez - 202521423
-- Lissette Johana Patiño Quinayas - 202520977
-- =============================================================================
-- Requisitos:
--   * La base tiene el esquema anterior (01_esquema.sql) con datos cargados.
--   * libros_semilla.csv accesible desde el servidor (por defecto /scripts/datos/).
--   * Respaldo previo:
--       pg_dump -U curso -d curso > respaldo_antes_normalizacion.sql
--
-- Uso (desde entorno-docker/, con este archivo y el CSV dentro de postgres/scripts/):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/normalizacion.sql
--   docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/otro.csv -f /scripts/normalizacion.sql
--
-- Decisiones del equipo:
--   * ISBN: se toma de libros_semilla.csv, porque libro.codigo guardó solo los últimos 9 caracteres cuando el ISBN esta compuesto por 13.
--   * Plazo: no se guarda fecha_esperada. La mora se calcula con plazo_prestamo_dias()
--     (normalizacion.md 3.9).
--
-- Si un prechequeo o una verificación falla, psql se detiene sin COMMIT y la base queda como estaba.
-- Los objetos derivados (función, vistas, índice y restricciones) deben coincidir con postgres/init/. Los archivos de auditoría van al esquema migracion_archivo, para que
-- biblioteca quede igual a la que crea init/.
-- =============================================================================
 
\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
\endif
 
SET search_path TO biblioteca, public;
 
BEGIN;
 
-- -----------------------------------------------------------------------------
-- 0. Guarda: se comprueba si ya se realizo migracion
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('biblioteca.creado_por') IS NULL THEN
    RAISE EXCEPTION 'No existe biblioteca.creado_por: la base no está en el esquema anterior (¿ya se migró?).';
  END IF;
  IF to_regclass('biblioteca.editorial') IS NOT NULL THEN
    RAISE EXCEPTION 'biblioteca.editorial ya existe: la migración ya se corrió.';
  END IF;
END $$;
 
-- -----------------------------------------------------------------------------
-- 1. Tabla temporal para leer los ISBN de libros_semilla.csv
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE csv_raw (n serial, linea text) ON COMMIT DROP;
COPY csv_raw (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM csv_raw WHERE n = 1;   -- encabezado
 
CREATE TEMP TABLE csv_isbn ON COMMIT DROP AS
SELECT trim(split_part(linea, ',', 1)) AS isbn
FROM   csv_raw;
 
-- -----------------------------------------------------------------------------
-- 2. Conteos esperados
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE esperado ON COMMIT DROP AS
SELECT (SELECT count(*) FROM libro)     AS n_libros,
       (SELECT count(*) FROM unidad)    AS n_unidades,
       (SELECT count(*) FROM prestamo)  AS n_prestamos,
       (SELECT count(*) FROM creado_por) AS n_creado_por,
       (SELECT count(*) FROM (
            SELECT DISTINCT l.codigo, trim(x.nombre)
            FROM   libro l
            CROSS JOIN LATERAL unnest(string_to_array(l.autor, ';')) AS x(nombre)
            WHERE  trim(x.nombre) <> '') p) AS n_pares_autor;
 
-- -----------------------------------------------------------------------------
-- 3. Prechequeos: si algo de esto ocurre, si hay conflictos la migracion se detiene
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  n integer;
BEGIN
  -- ISBN de longitud correcta y unicos(si hay dos ISBN con los mismos 9 últimos dígitos, generaria problemas en el codigo)
  SELECT count(*) INTO n FROM csv_isbn WHERE isbn !~ '^[0-9]{13}$';
  IF n > 0 THEN
    RAISE EXCEPTION 'Hay % ISBN del CSV que no tienen 13 dígitos', n;
  END IF;
 
  SELECT count(*) INTO n
  FROM (SELECT right(isbn, 9) FROM csv_isbn GROUP BY right(isbn, 9) HAVING count(*) > 1) x;
  IF n > 0 THEN
    RAISE EXCEPTION 'Hay % códigos repetidos en el CSV (dos ISBN con los mismos 9 últimos dígitos)', n;
  END IF;
 
  -- Existe ISBN para cada libro de la base
  SELECT count(*) INTO n FROM libro l
  WHERE  NOT EXISTS (SELECT 1 FROM csv_isbn c WHERE right(c.isbn, 9)::integer = l.codigo);
  IF n > 0 THEN
    RAISE EXCEPTION 'Hay % libros de la base sin ISBN en el CSV: ¿es el CSV correcto?', n;
  END IF;
 
  -- Una unidad no puede tener más de un préstamo abierto (regla que el documento verifica en §7)
  SELECT count(*) INTO n
  FROM (SELECT codigo FROM prestamo WHERE fecha_devolucion IS NULL
        GROUP BY codigo HAVING count(*) > 1) x;
  IF n > 0 THEN
    RAISE EXCEPTION 'Hay % unidades con más de un préstamo abierto', n;
  END IF;
 
  -- El libro de cada préstamo debe ser el de su unidad
  SELECT count(*) INTO n
  FROM   prestamo p
  JOIN   unidad u ON u.codigo_unit = p.codigo
  WHERE  p.codigo_libro <> u.codigo_libro;
  IF n > 0 THEN
    RAISE EXCEPTION 'Hay % préstamos cuyo libro no coincide con el de su unidad', n;
  END IF;
 
  -- Ninguna devolución anterior al préstamo (CHECK prestamo_fechas_ok)
  SELECT count(*) INTO n FROM prestamo WHERE fecha_devolucion < fecha_prestamo;
  IF n > 0 THEN
    RAISE EXCEPTION 'Hay % préstamos con devolución anterior al préstamo', n;
  END IF;
END $$;
 
-- -----------------------------------------------------------------------------
-- 4. Crear las tablas nuevas: catálogos y tabla puente
--    varchar sin longitud, igual que las columnas que reemplazan
-- -----------------------------------------------------------------------------
CREATE TABLE editorial (
    id_editorial integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       varchar NOT NULL UNIQUE
);
 
CREATE TABLE genero (
    id_genero integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    varchar NOT NULL UNIQUE
);
 
CREATE TABLE autor (
    id_autor integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre   varchar NOT NULL UNIQUE
);
 
CREATE TABLE libro_autor (
    codigo_libro integer NOT NULL REFERENCES libro (codigo),
    id_autor     integer NOT NULL REFERENCES autor (id_autor),
    PRIMARY KEY (codigo_libro, id_autor)
);
 
-- -----------------------------------------------------------------------------
-- 5. Copiar con INSERT ... SELECT
-- -----------------------------------------------------------------------------
-- Catálogos. 'Editorial General' es el valor por defecto que usa la carga de libros.
INSERT INTO editorial (nombre)
SELECT DISTINCT editorial FROM libro;
 
INSERT INTO editorial (nombre) VALUES ('Editorial General')
ON CONFLICT (nombre) DO NOTHING;
 
INSERT INTO genero (nombre)
SELECT DISTINCT genero FROM libro;
 
INSERT INTO autor (nombre)
SELECT DISTINCT trim(x.nombre)
FROM   libro l
CROSS JOIN LATERAL unnest(string_to_array(l.autor, ';')) AS x(nombre)
WHERE  trim(x.nombre) <> '';
 
-- Columnas nuevas en libro. El ISBN sale del CSV, no de la base.
ALTER TABLE libro
    ADD COLUMN isbn         varchar(13),
    ADD COLUMN id_genero    integer,
    ADD COLUMN id_editorial integer;
 
UPDATE libro l SET id_genero    = g.id_genero    FROM genero g    WHERE g.nombre = l.genero;
UPDATE libro l SET id_editorial = e.id_editorial FROM editorial e WHERE e.nombre = l.editorial;
UPDATE libro l SET isbn         = c.isbn         FROM csv_isbn c  WHERE right(c.isbn, 9)::integer = l.codigo;
 
-- Tabla puente: una fila por (libro, autor). Cada coautor sale de separar por ';'.
INSERT INTO libro_autor (codigo_libro, id_autor)
SELECT DISTINCT l.codigo, a.id_autor
FROM   libro l
CROSS JOIN LATERAL unnest(string_to_array(l.autor, ';')) AS x(nombre)
JOIN   autor a ON a.nombre = trim(x.nombre)
WHERE  trim(x.nombre) <> '';
 
-- -----------------------------------------------------------------------------
-- 6. Verificar libro y autores. Se comprueban el n de columnas esperadas
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  e_lib integer;  e_par integer;  n_par integer;
  sin_dato integer;  dif_lib integer;  dif_aut integer;
BEGIN
  SELECT n_libros, n_pares_autor INTO e_lib, e_par FROM esperado;
  IF (SELECT count(*) FROM libro) <> e_lib THEN
    RAISE EXCEPTION 'Libros: se esperaban % y hay %', e_lib, (SELECT count(*) FROM libro);
  END IF;
 
  SELECT count(*) INTO sin_dato FROM libro
  WHERE  isbn IS NULL OR id_genero IS NULL OR id_editorial IS NULL;
  IF sin_dato > 0 THEN
    RAISE EXCEPTION 'Hay % libros sin ISBN, género o editorial', sin_dato;
  END IF;
 
  -- Libro: valores originales vs. valores reconstruidos desde los catálogos y viceversa
  SELECT count(*) INTO dif_lib FROM (
      (SELECT codigo, isbn, titulo, edicion, genero, editorial FROM libro
       EXCEPT
       SELECT l.codigo, l.isbn, l.titulo, l.edicion, g.nombre, e.nombre
       FROM   libro l
       JOIN   genero g    USING (id_genero)
       JOIN   editorial e USING (id_editorial))
      UNION ALL
      (SELECT l.codigo, l.isbn, l.titulo, l.edicion, g.nombre, e.nombre
       FROM   libro l
       JOIN   genero g    USING (id_genero)
       JOIN   editorial e USING (id_editorial)
       EXCEPT
       SELECT codigo, isbn, titulo, edicion, genero, editorial FROM libro)) x;
 
  -- Autores: pares (libro, autor) del texto original contra la tabla puente
  SELECT count(*) INTO n_par FROM libro_autor;
  IF n_par <> e_par THEN
    RAISE EXCEPTION 'Pares libro-autor: se esperaban % y hay %', e_par, n_par;
  END IF;
 
  SELECT count(*) INTO dif_aut FROM (
      (SELECT DISTINCT l.codigo, trim(x.nombre) AS nombre
       FROM   libro l
       CROSS JOIN LATERAL unnest(string_to_array(l.autor, ';')) AS x(nombre)
       WHERE  trim(x.nombre) <> ''
       EXCEPT
       SELECT la.codigo_libro, a.nombre
       FROM   libro_autor la
       JOIN   autor a USING (id_autor))
      UNION ALL
      (SELECT la.codigo_libro, a.nombre
       FROM   libro_autor la
       JOIN   autor a USING (id_autor)
       EXCEPT
       SELECT DISTINCT l.codigo, trim(x.nombre)
       FROM   libro l
       CROSS JOIN LATERAL unnest(string_to_array(l.autor, ';')) AS x(nombre)
       WHERE  trim(x.nombre) <> '')) y;
 
  IF dif_lib > 0 OR dif_aut > 0 THEN
    RAISE EXCEPTION 'La reconstrucción de libro/autores no coincide: libro %, autores %', dif_lib, dif_aut;
  END IF;
END $$;
 
-- Restricciones del esquema nuevo en libro
ALTER TABLE libro
    ALTER COLUMN isbn SET NOT NULL,
    ADD CONSTRAINT libro_isbn_uk      UNIQUE (isbn),
    ADD CONSTRAINT libro_isbn_formato CHECK (isbn ~ '^[0-9]{13}$'),
    ALTER COLUMN id_genero SET NOT NULL,
    ADD CONSTRAINT libro_genero_fk    FOREIGN KEY (id_genero)    REFERENCES genero (id_genero),
    ALTER COLUMN id_editorial SET NOT NULL,
    ADD CONSTRAINT libro_editorial_fk FOREIGN KEY (id_editorial) REFERENCES editorial (id_editorial);
 
-- Una vez verificado que se reconstruyen las tablas og con exito, se dropean/eliminan las viejas
ALTER TABLE libro
    DROP COLUMN autor,
    DROP COLUMN genero,
    DROP COLUMN editorial;
 
-- -----------------------------------------------------------------------------
-- 7. Unidad y préstamo: disponibilidad y estado pasan a calcularse desde prestamo
-- -----------------------------------------------------------------------------
-- Archivo de auditoría: lo que la base tenía guardado frente a lo que dicen los préstamos.
CREATE SCHEMA IF NOT EXISTS migracion_archivo;
 
CREATE TABLE migracion_archivo.unidad_estado AS
SELECT u.codigo_unit,
       u.disponibilidad AS disponibilidad_guardada,
       u.estado         AS estado_guardado,
       NOT EXISTS (SELECT 1 FROM prestamo p
                   WHERE  p.codigo = u.codigo_unit AND p.fecha_devolucion IS NULL)
                        AS disponibilidad_calculada
FROM   unidad u;
 
DO $$
DECLARE
  e_uni integer;  n_arch integer;
BEGIN
  SELECT n_unidades INTO e_uni FROM esperado;
  SELECT count(*) INTO n_arch FROM migracion_archivo.unidad_estado;
  IF n_arch <> e_uni THEN
    RAISE EXCEPTION 'El archivo de unidades tiene % filas; se esperaban %', n_arch, e_uni;
  END IF;
END $$;
 
-- Préstamo: quitar codigo_libro. Con la columna se van la FK a libro y la FK compuesta a unidad.
ALTER TABLE prestamo DROP COLUMN codigo_libro;
 
-- Unidad: quitar lo derivado, el identificador sustituto y la clave compuesta que solo servía a la FK compuesta.
ALTER TABLE unidad
    DROP COLUMN disponibilidad,
    DROP COLUMN estado,
    DROP COLUMN codigo,
    DROP CONSTRAINT unidad_unit_libro_uk;
 
-- Restricciones del esquema nuevo
ALTER TABLE unidad
    ADD CONSTRAINT unidad_libro_coincide CHECK (split_part(codigo_unit, '-', 2)::integer = codigo_libro);
 
ALTER TABLE prestamo
    ADD CONSTRAINT prestamo_unidad_fk   FOREIGN KEY (codigo) REFERENCES unidad (codigo_unit),
    ADD CONSTRAINT prestamo_fechas_ok   CHECK (fecha_devolucion >= fecha_prestamo);
 
CREATE INDEX prestamo_abiertos_idx ON prestamo (codigo) WHERE fecha_devolucion IS NULL;
 
-- -----------------------------------------------------------------------------
-- 8. creado_por: de tabla a columna de cuenta_usuario (cuenta del creador)
-- -----------------------------------------------------------------------------
ALTER TABLE cuenta_usuario
    ADD COLUMN creado_por integer REFERENCES cuenta_usuario (id_cuenta);
 
-- id_empleado del creador -> id_cuenta de ese bibliotecario
UPDATE cuenta_usuario c
SET    creado_por = b.id_cuenta
FROM   creado_por cp
JOIN   bibliotecario b ON b.id_empleado = cp.id_empleado
WHERE  c.id_cuenta = cp.id_cuenta;
 
DO $$
DECLARE
  e_cp integer;  n_cp integer;
BEGIN
  SELECT n_creado_por INTO e_cp FROM esperado;
  SELECT count(*) INTO n_cp FROM cuenta_usuario WHERE creado_por IS NOT NULL;
  IF n_cp <> e_cp THEN
    RAISE EXCEPTION 'creado_por: se esperaban % cuentas con creador y hay %', e_cp, n_cp;
  END IF;
END $$;
 
DROP TABLE creado_por;
 
-- -----------------------------------------------------------------------------
-- 9. Objetos derivados (mismo DDL que postgres/init/)
-- -----------------------------------------------------------------------------
-- Plazo fijo de 14 días. Cambiarlo recalcula también la mora de los préstamos anteriores.
CREATE OR REPLACE FUNCTION plazo_prestamo_dias() RETURNS integer
LANGUAGE sql IMMUTABLE AS $$ SELECT 14 $$;
 
-- Una fila por unidad, aunque tenga varios préstamos abiertos (durante la carga puede pasar)
CREATE VIEW v_unidad AS
SELECT u.codigo_unit,
       u.codigo_libro,
       NOT EXISTS (SELECT 1 FROM prestamo p
                   WHERE  p.codigo = u.codigo_unit AND p.fecha_devolucion IS NULL) AS disponibilidad,
       EXISTS (SELECT 1 FROM prestamo p
               WHERE  p.codigo = u.codigo_unit AND p.fecha_devolucion IS NULL
                 AND  p.fecha_prestamo + plazo_prestamo_dias() < CURRENT_DATE)     AS estado
FROM   unidad u;
 
CREATE VIEW v_prestamo_en_mora AS
SELECT p.id_prestamo,
       p.id_lector,
       p.codigo,
       p.fecha_prestamo,
       p.fecha_prestamo + plazo_prestamo_dias() AS fecha_esperada
FROM   prestamo p
WHERE  p.fecha_devolucion IS NULL
  AND  p.fecha_prestamo + plazo_prestamo_dias() < CURRENT_DATE;
 
-- -----------------------------------------------------------------------------
-- 10. Verificación final de conteos
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  e_uni integer;  e_pre integer;  n integer;
BEGIN
  SELECT n_unidades, n_prestamos INTO e_uni, e_pre FROM esperado;
 
  SELECT count(*) INTO n FROM v_unidad;
  IF n <> e_uni THEN
    RAISE EXCEPTION 'v_unidad devuelve % filas; se esperaban %', n, e_uni;
  END IF;
 
  SELECT count(*) INTO n FROM prestamo;
  IF n <> e_pre THEN
    RAISE EXCEPTION 'prestamo tiene % filas; se esperaban %', n, e_pre;
  END IF;
END $$;
 
COMMIT;