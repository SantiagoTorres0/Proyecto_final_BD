-- =============================================================================
-- S14-carga-prestamos.sql — prestamo.csv -> biblioteca.prestamo
-- =============================================================================
-- Uso:
--   psql -U curso -d curso -f /scripts/S14-carga-prestamos.sql
--   psql -U curso -d curso -v archivo=/scripts/datos/otro.csv -f /scripts/S14-carga-prestamos.sql
--
-- CSV esperado (6 columnas, con encabezado):
--   id_prestamo,fecha_prestamo,codigo_libro,id_lector,codigo,id_empleado
--
-- Qué arregla respecto al script anterior (datos-prueba.sql, sección B):
--   * stg_prestamo.fecha_prestamo era DATE: una fecha mala abortaba el COPY
--     completo. Ahora es texto y se valida con es_fecha() (que también caza
--     fechas imposibles como 2026-02-31).
--   * No se comprobaba que el libro existiera ni que la unidad pertenezca a
--     ESE libro (el CSV podía decir libro 3 con la unidad U-001-1).
--   * No se detectaban id_prestamo repetidos (PK).
--   * Mismo problema de `contenido` NOT NULL en la bitácora.
--
-- Reglas de rechazo (primera que falle):
--   columnas <> 6 · id_prestamo, fecha, libro, lector, empleado vacíos o con
--   formato inválido · unidad vacía · id_prestamo ya existe · libro, lector,
--   bibliotecario o unidad inexistentes · la unidad no es de ese libro ·
--   id_prestamo repetido en el archivo.
--
-- Nota de negocio: NO se exige que la unidad figure como no disponible. En los
-- datos semilla solo 4 de 20 préstamos están "abiertos" (U-003-1, U-005-2,
-- U-008-1, U-010-2); los demás son históricos y no tienen fecha de devolución
-- en el CSV, así que no se puede inferir cuáles siguen pendientes.
--
-- Ejecutar DESPUÉS de libros, lectores, bibliotecarios y unidades.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/prestamo.csv
\endif

SET search_path TO biblioteca, public;

BEGIN;

TRUNCATE stg_linea, stg_prestamo RESTART IDENTITY;

-- 1. Leer el archivo tal cual
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir en campos
INSERT INTO stg_prestamo (linea_csv, contenido, num_campos, id_prestamo,
                          fecha_prestamo, codigo_libro, id_lector, codigo, id_empleado)
SELECT n, linea,
       length(linea) - length(replace(linea, ',', '')) + 1,
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       trim(split_part(linea, ',', 4)),
       trim(split_part(linea, ',', 5)),
       trim(split_part(linea, ',', 6))
FROM stg_linea;

-- 3. Validar
UPDATE stg_prestamo SET motivo = CASE
    WHEN num_campos <> 6                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
    WHEN id_prestamo !~ '^[0-9]{1,9}$'            THEN 'id_prestamo vacío o no es un entero válido'
    WHEN NOT es_fecha(fecha_prestamo)             THEN 'fecha_prestamo vacía o no es una fecha válida (AAAA-MM-DD)'
    WHEN codigo_libro !~ '^[0-9]{1,9}$'           THEN 'código de libro vacío o no es un entero válido'
    WHEN id_lector !~ '^[0-9]{1,15}$'             THEN 'lector no especificado o no numérico'
    WHEN codigo = ''                              THEN 'unidad de libro no especificada'
    WHEN id_empleado !~ '^[0-9]{1,9}$'            THEN 'bibliotecario no especificado o no numérico'
    WHEN EXISTS (SELECT 1 FROM prestamo p WHERE p.id_prestamo = stg_prestamo.id_prestamo::integer)
                                                  THEN 'el préstamo ya existe en el sistema'
    WHEN NOT EXISTS (SELECT 1 FROM libro l WHERE l.codigo = stg_prestamo.codigo_libro::integer)
                                                  THEN 'el libro no existe en el catálogo'
    WHEN NOT EXISTS (SELECT 1 FROM lector l WHERE l.documento = stg_prestamo.id_lector::bigint)
                                                  THEN 'el lector no existe en el sistema'
    WHEN NOT EXISTS (SELECT 1 FROM bibliotecario b WHERE b.id_empleado = stg_prestamo.id_empleado::integer)
                                                  THEN 'el bibliotecario no existe en el sistema'
    WHEN NOT EXISTS (SELECT 1 FROM unidad u WHERE u.codigo_unit = stg_prestamo.codigo)
                                                  THEN 'la unidad física del libro no existe'
    WHEN NOT EXISTS (SELECT 1 FROM unidad u
                     WHERE u.codigo_unit = stg_prestamo.codigo
                       AND u.codigo_libro = stg_prestamo.codigo_libro::integer)
                                                  THEN 'la unidad no pertenece al libro indicado'
END;

-- 4. id_prestamo repetido dentro del archivo
UPDATE stg_prestamo SET motivo = 'id_prestamo repetido en el archivo'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_prestamo s2
              WHERE s2.id_prestamo::integer = stg_prestamo.id_prestamo::integer
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_prestamo.linea_csv);

-- 5. Filas válidas -> prestamo
INSERT INTO prestamo (id_prestamo, fecha_prestamo, codigo_libro, id_lector, codigo, id_empleado)
SELECT id_prestamo::integer, fecha_prestamo::date, codigo_libro::integer,
       id_lector::bigint, codigo, id_empleado::integer
FROM stg_prestamo
WHERE motivo IS NULL
ORDER BY linea_csv;

-- 6. Rechazos -> bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_prestamo
WHERE motivo IS NOT NULL;

COMMIT;

SELECT count(*) FILTER (WHERE motivo IS NULL)     AS prestamos_cargados,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazados
FROM stg_prestamo;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_prestamo
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
