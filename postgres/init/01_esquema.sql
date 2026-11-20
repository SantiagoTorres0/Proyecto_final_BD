-- =============================================================================
-- 01_esquema.sql — Esquema `biblioteca` (DDL) · versión NORMALIZADA (Hito 3)
-- =============================================================================
-- Crea el esquema completo desde cero. DESTRUCTIVO: borra `biblioteca` entero
-- (DROP SCHEMA ... CASCADE), así que solo debe correr al inicializar la base.
--
-- Orden de ejecución:   01_esquema.sql  ->  02_staging.sql  ->  datos-prueba.sql
--
-- Modelo (resumen):
--
--   cuenta_usuario 1──1 lector            lector 1──* prestamo
--   cuenta_usuario 1──1 bibliotecario     bibliotecario 1──* prestamo
--   cuenta_usuario 1──* cuenta_usuario    (creado_por: quién creó la cuenta)
--   libro          1──* unidad            unidad 1──* prestamo
--   libro *──* autor     (vía libro_autor)
--   libro *──1 genero    libro *──1 editorial
--
-- Cambios de normalización respecto a la versión anterior (ver el documento
-- de normalización para el análisis completo de dependencias funcionales):
--   * libro: se agrega isbn (UNIQUE) y se extraen los catálogos editorial,
--     genero y autor (+ tabla puente libro_autor para la coautoría, 1FN).
--   * unidad: se eliminan disponibilidad y estado (datos DERIVADOS de
--     prestamo; se exponen mediante la vista v_unidad). Se elimina la columna
--     sustituta `codigo` (codigo_unit ya es la clave) y se agrega un CHECK que
--     obliga a que el libro codificado en codigo_unit coincida con codigo_libro.
--   * prestamo: sin codigo_libro (dependencia transitiva, ya eliminada). La
--     regla "una unidad solo puede tener UN préstamo abierto" NO se declara
--     como índice único parcial: prestamo.csv no trae fecha_devolucion (la
--     aplica después devoluciones.csv) y el índice rechazaría los préstamos
--     históricos de una misma unidad durante la carga. Se verifica al final de
--     S14-carga-devoluciones.sql y la hará cumplir el trigger/procedimiento del
--     Hito 4.
--   * creado_por: la tabla auxiliar desaparece; ahora es la columna
--     cuenta_usuario.creado_por (auto-referencia a cuenta_usuario).
--   * Errores de sintaxis corregidos (coma faltante, ALTER_TABLE, FK circular,
--     COMMENT sobre una columna inexistente).
--   * NO se separa lector.nombre / bibliotecario.nombre en nombres y apellidos
--     (decisión explícita del equipo).
-- =============================================================================

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS biblioteca CASCADE;
CREATE SCHEMA biblioteca;
SET search_path TO biblioteca;

-- -----------------------------------------------------------------------------
-- Perfiles de usuario
-- -----------------------------------------------------------------------------
CREATE TYPE tipo_perfil AS ENUM (
  'bibliotecario',
  'administrador',
  'lector',
  'auditor'
);

-- -----------------------------------------------------------------------------
-- Cuentas de acceso (padre de lector y bibliotecario)
-- -----------------------------------------------------------------------------
-- creado_por referencia a la cuenta que creó esta cuenta (un administrador crea
-- cuentas de bibliotecario; un bibliotecario crea cuentas de lector). Es NULL
-- para cuentas iniciales/semilla. Reemplaza a la antigua tabla creado_por.
CREATE TABLE cuenta_usuario (
  id_cuenta        integer     PRIMARY KEY,
  perfil           tipo_perfil NOT NULL,
  login_nombre     varchar     UNIQUE NOT NULL,
  login_contrasena varchar     NOT NULL,
  creado_por       integer
);
ALTER TABLE cuenta_usuario
  ADD CONSTRAINT cuenta_usuario_creado_por_fk
  FOREIGN KEY (creado_por) REFERENCES cuenta_usuario (id_cuenta)
  DEFERRABLE INITIALLY IMMEDIATE;

-- -----------------------------------------------------------------------------
-- Personas
-- -----------------------------------------------------------------------------
CREATE TABLE lector (
  documento bigint  PRIMARY KEY,                   -- bigint: documentos de 10+ dígitos
  id_cuenta integer UNIQUE NOT NULL,
  nombre    varchar NOT NULL,
  correo    varchar UNIQUE,
  telefono  varchar NOT NULL
);
ALTER TABLE lector ADD FOREIGN KEY (id_cuenta) REFERENCES cuenta_usuario (id_cuenta) DEFERRABLE INITIALLY IMMEDIATE;

CREATE TABLE bibliotecario (
  id_empleado integer PRIMARY KEY,
  id_cuenta   integer UNIQUE NOT NULL,
  nombre      varchar NOT NULL
);
ALTER TABLE bibliotecario ADD FOREIGN KEY (id_cuenta) REFERENCES cuenta_usuario (id_cuenta) DEFERRABLE INITIALLY IMMEDIATE;

-- -----------------------------------------------------------------------------
-- Catálogos del libro (extraídos de libro)
-- -----------------------------------------------------------------------------
CREATE TABLE editorial (
  id_editorial integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre       varchar UNIQUE NOT NULL
);

CREATE TABLE genero (
  id_genero integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre    varchar UNIQUE NOT NULL
);

CREATE TABLE autor (
  id_autor integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre   varchar UNIQUE NOT NULL
);

-- -----------------------------------------------------------------------------
-- Catálogo de libros
-- -----------------------------------------------------------------------------
CREATE TABLE libro (
  codigo       integer    PRIMARY KEY,
  isbn         varchar(13) UNIQUE NOT NULL,
  titulo       varchar    NOT NULL,
  edicion      varchar    NOT NULL,
  id_genero    integer    NOT NULL,
  id_editorial integer    NOT NULL,
  CONSTRAINT libro_formato_isbn CHECK (isbn ~ '^[0-9]{13}$')
);
ALTER TABLE libro ADD FOREIGN KEY (id_genero)    REFERENCES genero (id_genero)       DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE libro ADD FOREIGN KEY (id_editorial) REFERENCES editorial (id_editorial) DEFERRABLE INITIALLY IMMEDIATE;

-- Puente libro <-> autor (un libro puede tener varios autores; un autor varios libros)
CREATE TABLE libro_autor (
  codigo_libro integer NOT NULL,
  id_autor     integer NOT NULL,
  PRIMARY KEY (codigo_libro, id_autor)
);
ALTER TABLE libro_autor ADD FOREIGN KEY (codigo_libro) REFERENCES libro (codigo)   DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE libro_autor ADD FOREIGN KEY (id_autor)     REFERENCES autor (id_autor) DEFERRABLE INITIALLY IMMEDIATE;

-- -----------------------------------------------------------------------------
-- Ejemplares físicos
-- -----------------------------------------------------------------------------
-- disponibilidad y estado (mora) YA NO se almacenan: se derivan de prestamo
-- (ver vista v_unidad).
CREATE TABLE unidad (
  codigo_unit  varchar PRIMARY KEY,
  codigo_libro integer NOT NULL,
  CONSTRAINT unidad_formato_codigo CHECK (codigo_unit ~ '^U-[0-9]{3,}-[0-9]+$'),
  -- El libro codificado en U-LLL-N debe ser el mismo codigo_libro (evita la
  -- dependencia redundante codigo_unit -> codigo_libro escrita dos veces).
  CONSTRAINT unidad_libro_coincide CHECK (
    CASE WHEN codigo_unit ~ '^U-[0-9]{3,}-[0-9]+$'
         THEN split_part(codigo_unit, '-', 2)::integer = codigo_libro
         ELSE false END
  )
);
ALTER TABLE unidad ADD FOREIGN KEY (codigo_libro) REFERENCES libro (codigo) DEFERRABLE INITIALLY IMMEDIATE;

-- -----------------------------------------------------------------------------
-- Préstamos
-- -----------------------------------------------------------------------------
CREATE TABLE prestamo (
  id_prestamo      integer PRIMARY KEY,
  fecha_prestamo   date    NOT NULL,
  fecha_devolucion date,
  id_lector        bigint  NOT NULL,
  codigo           varchar NOT NULL,   -- unidad.codigo_unit
  id_empleado      integer NOT NULL,
  CONSTRAINT prestamo_fechas_ok CHECK (fecha_devolucion IS NULL OR fecha_devolucion >= fecha_prestamo)
);

ALTER TABLE prestamo ADD FOREIGN KEY (id_lector)   REFERENCES lector (documento)           DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE prestamo ADD FOREIGN KEY (id_empleado) REFERENCES bibliotecario (id_empleado)  DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE prestamo ADD FOREIGN KEY (codigo)      REFERENCES unidad (codigo_unit)         DEFERRABLE INITIALLY IMMEDIATE;

-- Regla (Hito 4): una unidad solo puede tener un préstamo abierto (sin devolución)
-- a la vez. No se declara aquí como índice único parcial; ver cabecera.
-- Apoyo para las consultas de disponibilidad y mora:
CREATE INDEX prestamo_abiertos_idx ON prestamo (codigo) WHERE fecha_devolucion IS NULL;

-- -----------------------------------------------------------------------------
-- Regla de negocio parametrizable: plazo de préstamo (definición §3.2: 14 días)
-- -----------------------------------------------------------------------------
CREATE FUNCTION plazo_prestamo_dias() RETURNS integer
LANGUAGE sql IMMUTABLE AS $$ SELECT 14 $$;

-- -----------------------------------------------------------------------------
-- Vistas con los datos derivados (antes columnas almacenadas en unidad)
-- -----------------------------------------------------------------------------
-- disponibilidad: true  = la unidad no tiene préstamo abierto (está en el estante)
-- estado (mora) : true  = tiene un préstamo abierto cuyo plazo ya venció
-- Equivale a la antigua regla CHECK "disponible no puede estar en mora": una
-- unidad sin préstamo abierto nunca puede estar en mora.
CREATE VIEW v_unidad AS
SELECT u.codigo_unit,
       u.codigo_libro,
       NOT EXISTS (SELECT 1 FROM prestamo p
                   WHERE p.codigo = u.codigo_unit
                     AND p.fecha_devolucion IS NULL)                  AS disponibilidad,
       EXISTS     (SELECT 1 FROM prestamo p
                   WHERE p.codigo = u.codigo_unit
                     AND p.fecha_devolucion IS NULL
                     AND p.fecha_prestamo + plazo_prestamo_dias() < CURRENT_DATE) AS estado
FROM unidad u;

-- Préstamos abiertos vencidos (base del reporte de morosos y de las notificaciones)
CREATE VIEW v_prestamo_en_mora AS
SELECT p.id_prestamo,
       p.id_lector,
       p.codigo,
       p.fecha_prestamo,
       p.fecha_prestamo + plazo_prestamo_dias() AS fecha_esperada_devolucion,
       CURRENT_DATE - (p.fecha_prestamo + plazo_prestamo_dias()) AS dias_mora
FROM prestamo p
WHERE p.fecha_devolucion IS NULL
  AND p.fecha_prestamo + plazo_prestamo_dias() < CURRENT_DATE;

-- -----------------------------------------------------------------------------
-- Documentación dentro de la propia base (visible con \d+ y \dt+)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE  cuenta_usuario IS 'Credenciales de acceso. Cada lector o bibliotecario tiene exactamente una cuenta.';
COMMENT ON TABLE  lector         IS 'Personas que piden libros prestados. Se cargan desde lectores_semilla.csv.';
COMMENT ON TABLE  bibliotecario  IS 'Empleados que registran préstamos. Se cargan desde bibliotecario.csv.';
COMMENT ON TABLE  editorial      IS 'Catálogo de editoriales (extraído de libro por normalización).';
COMMENT ON TABLE  genero         IS 'Catálogo de géneros/categorías (extraído de libro por normalización).';
COMMENT ON TABLE  autor          IS 'Catálogo de autores (extraído de libro por normalización).';
COMMENT ON TABLE  libro          IS 'Catálogo (título). Se carga desde libros_semilla.csv.';
COMMENT ON TABLE  libro_autor    IS 'Puente N:M libro-autor: permite coautoría sin violar 1FN.';
COMMENT ON TABLE  unidad         IS 'Ejemplar físico de un libro. Se carga desde unidad.csv. No almacena disponibilidad ni mora: ver v_unidad.';
COMMENT ON TABLE  prestamo       IS 'Préstamo de UNA unidad a UN lector atendido por UN bibliotecario. Se carga desde prestamo.csv.';

COMMENT ON COLUMN cuenta_usuario.login_contrasena IS 'Hash de la contraseña (p. ej. bcrypt con salt). Nunca texto plano.';
COMMENT ON COLUMN cuenta_usuario.creado_por       IS 'Cuenta que creó esta cuenta (NULL en cuentas iniciales). Reemplaza la tabla creado_por.';
COMMENT ON COLUMN libro.codigo          IS 'Derivado del ISBN al cargar: últimos 9 dígitos como entero (ISBN 9780000000012 -> 12).';
COMMENT ON COLUMN libro.isbn            IS 'ISBN-13 completo (13 dígitos). Clave candidata junto con codigo.';
COMMENT ON COLUMN unidad.codigo_unit    IS 'Nomenclatura U-LLL-N: LLL = código del libro (3+ dígitos), N = número de ejemplar. Ej.: U-001-1.';
COMMENT ON COLUMN prestamo.codigo       IS 'codigo_unit de la unidad prestada. El libro se obtiene por JOIN con unidad.';
COMMENT ON VIEW   v_unidad              IS 'Unidad con disponibilidad (sin préstamo abierto) y estado=mora (préstamo abierto vencido) CALCULADOS.';
COMMENT ON VIEW   v_prestamo_en_mora    IS 'Préstamos abiertos cuyo plazo (plazo_prestamo_dias) ya venció.';
