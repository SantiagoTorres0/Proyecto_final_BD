-- =============================================================================
-- 02_staging.sql — Bitácora de rechazos, tablas de paso y utilidades de carga
-- =============================================================================
-- Estrategia de carga (laboratorio S14), en 5 pasos que repiten TODOS los
-- scripts S14-carga-*.sql:
--
--   1. COPY del CSV a stg_linea, UNA FILA POR LÍNEA, sin interpretar nada.
--      (Así una línea con columnas de más o de menos no tumba la carga:
--       COPY ... FORMAT csv abortaría todo el archivo al primer error.)
--   2. Partir cada línea por comas hacia la tabla stg_<entidad> (todo texto).
--   3. Validar con un UPDATE ... CASE: la PRIMERA regla que falla deja su
--      motivo en la fila; las filas con motivo NULL son válidas.
--   4. Insertar a las tablas reales solo las filas con motivo NULL.
--   5. Registrar las demás en rechazo_carga (archivo, línea, contenido, motivo).
--
-- Todo texto en staging = ningún CAST puede fallar al cargar; los CAST solo se
-- hacen DESPUÉS de que una regla haya comprobado el formato.
--
-- Limitación conocida: se parte por comas "a pelo", por lo que un campo entre
-- comillas que contenga una coma (p. ej. "Gómez, Ana") se contaría como dos
-- columnas y la línea se rechazaría por número de columnas. Los CSV semilla
-- no tienen ese caso.
-- =============================================================================

\set ON_ERROR_STOP on

SET search_path TO biblioteca;

-- Bitácora de rechazos de todas las cargas
CREATE TABLE rechazo_carga (
  id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  archivo   text NOT NULL,
  linea     integer NOT NULL,          -- línea física en el CSV (encabezado = 1)
  contenido text NOT NULL,             -- la línea completa, tal cual venía
  motivo    text NOT NULL,
  fecha     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE rechazo_carga IS 'Filas de los CSV que no pasaron validación, con su motivo.';

-- Línea cruda. n = número de línea física: el encabezado es n=1, así que los
-- datos empiezan en n=2 (el mismo número que muestra un editor de texto).
CREATE TABLE stg_linea (
  n     integer GENERATED ALWAYS AS IDENTITY,
  linea text
);

CREATE TABLE stg_libro (
  linea_csv              integer,
  contenido              text,
  num_campos             integer,
  isbn                   text,
  titulo                 text,
  autor                  text,
  categoria              text,
  anio_publicacion       text,
  ejemplares_disponibles text,
  motivo                 text
);

CREATE TABLE stg_lector (
  linea_csv  integer,
  contenido  text,
  num_campos integer,
  documento  text,
  nombres    text,
  apellidos  text,
  correo     text,
  telefono   text,
  motivo     text
);

CREATE TABLE stg_bibliotecario (
  linea_csv   integer,
  contenido   text,
  num_campos  integer,
  id_empleado text,
  id_cuenta   text,
  nombre      text,
  motivo      text
);

CREATE TABLE stg_unidad (
  linea_csv      integer,
  contenido      text,
  num_campos     integer,
  codigo_libro   text,
  codigo_unit    text,
  disponibilidad text,
  estado         text,
  motivo         text
);

CREATE TABLE stg_prestamo (
  linea_csv      integer,
  contenido      text,
  num_campos     integer,
  id_prestamo    text,
  fecha_prestamo text,
  codigo_libro   text,
  id_lector      text,
  codigo         text,
  id_empleado    text,
  motivo         text
);

-- Utilidad: ¿es una fecha real? '2026-02-31' pasa una regex pero NO es fecha.
-- Un CAST directo abortaría la transacción; aquí el error se captura.
CREATE FUNCTION es_fecha(t text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  PERFORM t::date;
  RETURN t ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';   -- exige formato ISO estricto
EXCEPTION WHEN others THEN
  RETURN false;
END;
$$;
COMMENT ON FUNCTION es_fecha(text) IS 'true si el texto es una fecha ISO (AAAA-MM-DD) válida; nunca lanza error.';
