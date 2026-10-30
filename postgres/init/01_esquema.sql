-- =============================================================================
-- 01_esquema.sql — Esquema `biblioteca` (DDL)
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
--   libro          1──* unidad            unidad 1──* prestamo
--   libro          1──* prestamo (redundante a propósito, ver abajo)
--
-- Cambios respecto a la versión anterior (todos para que la carga CSV funcione):
--   * Los comentarios `// ...` NO son SQL (son sintaxis DBML): daban error de
--     sintaxis y abortaban todo el script. Ahora son `--` y COMMENT ON.
--   * unidad.codigo: era `integer NOT NULL` sin valor por defecto, y ningún CSV
--     lo trae -> el INSERT fallaba. Ahora es IDENTITY (se autogenera).
--   * unidad.codigo_libro: ahora NOT NULL (una unidad sin libro no tiene sentido).
--   * prestamo.codigo_libro: era varchar sin FK (y el CSV trae enteros). Ahora
--     es integer con FK a libro, y una FK compuesta garantiza que la unidad
--     prestada pertenezca realmente a ese libro.
--   * lector.documento / prestamo.id_lector: integer -> bigint. Los documentos
--     de 10+ dígitos (p. ej. 3001234567) desbordan integer (máx 2 147 483 647).
--   * CHECKs: formato del código de unidad y regla "disponible NO puede estar
--     en mora" (antes solo se validaba en el script de carga).
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
CREATE TABLE cuenta_usuario (
  id_cuenta        integer PRIMARY KEY,
  perfil           tipo_perfil NOT NULL,
  login_nombre     varchar UNIQUE NOT NULL,
  login_contrasena varchar NOT NULL
);

-- -----------------------------------------------------------------------------
-- Personas
-- -----------------------------------------------------------------------------
CREATE TABLE lector (
  documento bigint  PRIMARY KEY,                   -- bigint: ver cabecera
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
-- Catálogo
-- -----------------------------------------------------------------------------
CREATE TABLE libro (
  codigo    integer PRIMARY KEY,
  autor     varchar NOT NULL,
  titulo    varchar NOT NULL,
  edicion   varchar NOT NULL,
  genero    varchar NOT NULL,
  editorial varchar NOT NULL
);

-- Cada ejemplar físico de un libro.
CREATE TABLE unidad (
  codigo         integer GENERATED ALWAYS AS IDENTITY,   -- surrogate autogenerado
  codigo_libro   integer NOT NULL,
  codigo_unit    varchar PRIMARY KEY,                    -- 'U-001-1' = libro 1, unidad 1
  disponibilidad boolean NOT NULL,                       -- true = está en el estante
  estado         boolean NOT NULL,                       -- true = en mora (1), false = no (0)
  CONSTRAINT unidad_formato_codigo CHECK (codigo_unit ~ '^U-[0-9]{3,}-[0-9]+$'),
  CONSTRAINT unidad_disponible_no_mora CHECK (NOT (disponibilidad AND estado)),
  -- necesaria para la FK compuesta de prestamo
  CONSTRAINT unidad_unit_libro_uk UNIQUE (codigo_unit, codigo_libro)
);
ALTER TABLE unidad ADD FOREIGN KEY (codigo_libro) REFERENCES libro (codigo) DEFERRABLE INITIALLY IMMEDIATE;

-- -----------------------------------------------------------------------------
-- Préstamos
-- -----------------------------------------------------------------------------
CREATE TABLE prestamo (
  id_prestamo    integer PRIMARY KEY,
  fecha_prestamo date    NOT NULL,
  codigo_libro   integer NOT NULL,
  id_lector      bigint  NOT NULL,
  codigo         varchar NOT NULL,                       -- unidad.codigo_unit
  id_empleado    integer NOT NULL
);
ALTER TABLE prestamo ADD FOREIGN KEY (id_lector)   REFERENCES lector (documento)          DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE prestamo ADD FOREIGN KEY (id_empleado) REFERENCES bibliotecario (id_empleado) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE prestamo ADD FOREIGN KEY (codigo_libro) REFERENCES libro (codigo)             DEFERRABLE INITIALLY IMMEDIATE;
-- FK compuesta: la unidad prestada debe ser una unidad DE ESE libro.
ALTER TABLE prestamo ADD CONSTRAINT prestamo_unidad_del_libro_fk
  FOREIGN KEY (codigo, codigo_libro) REFERENCES unidad (codigo_unit, codigo_libro) DEFERRABLE INITIALLY IMMEDIATE;

-- -----------------------------------------------------------------------------
-- Tablas auxiliares del modelo (sin carga CSV por ahora)
-- -----------------------------------------------------------------------------
CREATE TABLE usuarios_instancias (
  bibliotecario varchar,
  administrador varchar,
  lector        varchar,
  auditor       varchar
);

-- Qué bibliotecario creó cada cuenta.
CREATE TABLE creado_por (
  id_empleado integer,
  id_cuenta   integer UNIQUE
);
ALTER TABLE creado_por ADD FOREIGN KEY (id_empleado) REFERENCES bibliotecario (id_empleado) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE creado_por ADD FOREIGN KEY (id_cuenta)   REFERENCES cuenta_usuario (id_cuenta)  DEFERRABLE INITIALLY IMMEDIATE;

-- -----------------------------------------------------------------------------
-- Documentación dentro de la propia base (visible con \d+ y \dt+)
-- -----------------------------------------------------------------------------
COMMENT ON TABLE  cuenta_usuario IS 'Credenciales de acceso. Cada lector o bibliotecario tiene exactamente una cuenta.';
COMMENT ON TABLE  lector         IS 'Personas que piden libros prestados. Se cargan desde lectores_semilla.csv.';
COMMENT ON TABLE  bibliotecario  IS 'Empleados que registran préstamos. Se cargan desde bibliotecario.csv.';
COMMENT ON TABLE  libro          IS 'Catálogo (título). Se carga desde libros_semilla.csv.';
COMMENT ON TABLE  unidad         IS 'Ejemplar físico de un libro. Se carga desde unidad.csv.';
COMMENT ON TABLE  prestamo       IS 'Préstamo de UNA unidad a UN lector atendido por UN bibliotecario. Se carga desde prestamo.csv.';

COMMENT ON COLUMN libro.codigo          IS 'Derivado del ISBN al cargar: últimos 9 dígitos como entero (ISBN 9780000000012 -> 12).';
COMMENT ON COLUMN unidad.codigo         IS 'Identificador autogenerado (IDENTITY). No viene en el CSV.';
COMMENT ON COLUMN unidad.codigo_unit    IS 'Nomenclatura U-LLL-N: LLL = código del libro (3+ dígitos), N = número de ejemplar. Ej.: U-001-1.';
COMMENT ON COLUMN unidad.disponibilidad IS 'true = disponible en el estante; false = prestada.';
COMMENT ON COLUMN unidad.estado         IS 'true = en mora (1); false = no está en mora (0). Una unidad disponible nunca puede estar en mora.';
COMMENT ON COLUMN prestamo.codigo       IS 'codigo_unit de la unidad prestada.';
COMMENT ON COLUMN prestamo.codigo_libro IS 'Libro de la unidad. La FK compuesta obliga a que coincida con la unidad.';
