-- =============================================================================
-- S14-carga-bibliotecarios.sql — bibliotecario.csv -> cuenta_usuario + bibliotecario
-- =============================================================================
-- Uso:
--   psql -U curso -d curso -f /scripts/S14-carga-bibliotecarios.sql
--   psql -U curso -d curso -v archivo=/scripts/datos/otro.csv -f /scripts/S14-carga-bibliotecarios.sql
--
-- CSV esperado (3 columnas, con encabezado):
--   id_empleado,id_cuenta,nombre
--
-- Este archivo NO existía en la carga original: sin bibliotecarios, TODOS los
-- préstamos se rechazaban ("el bibliotecario no existe en el sistema").
--
-- Cada bibliotecario válido crea:
--   1. cuenta_usuario: perfil 'bibliotecario', id_cuenta = el del CSV,
--      login = 'bib' || id_empleado con 3 dígitos (bib001, bib002, ...),
--      contraseña inicial '123456'. El CSV no trae correo, de ahí el login
--      derivado.
--   2. bibliotecario.
--
-- Reglas de rechazo (primera que falle):
--   columnas <> 3 · id_empleado / id_cuenta vacíos o no numéricos · nombre
--   vacío · empleado ya existe · id_cuenta ya está tomado (típico si los
--   lectores se cargaron con ids que pisan 21..25) · login ya existe ·
--   id_empleado o id_cuenta repetidos en el archivo.
--
-- Ejecutar DESPUÉS de S14-carga-lectores.sql (ver nota sobre id_cuenta allí).
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/bibliotecario.csv
\endif

SET search_path TO biblioteca, public;

BEGIN;

TRUNCATE stg_linea, stg_bibliotecario RESTART IDENTITY;

-- 1. Leer el archivo tal cual
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir en campos
INSERT INTO stg_bibliotecario (linea_csv, contenido, num_campos,
                               id_empleado, id_cuenta, nombre)
SELECT n, linea,
       length(linea) - length(replace(linea, ',', '')) + 1,
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3))
FROM stg_linea;

-- 3. Validar
UPDATE stg_bibliotecario SET motivo = CASE
    WHEN num_campos <> 3                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 3'
    WHEN id_empleado = ''                         THEN 'id_empleado vacío'
    WHEN id_empleado !~ '^[0-9]{1,9}$'            THEN 'id_empleado no es un entero válido'
    WHEN id_cuenta = ''                           THEN 'id_cuenta vacío'
    WHEN id_cuenta !~ '^[0-9]{1,9}$'              THEN 'id_cuenta no es un entero válido'
    WHEN nombre = ''                              THEN 'nombre vacío'
    WHEN EXISTS (SELECT 1 FROM bibliotecario b WHERE b.id_empleado = stg_bibliotecario.id_empleado::integer)
                                                  THEN 'el empleado ya existe en el sistema'
    WHEN EXISTS (SELECT 1 FROM cuenta_usuario c WHERE c.id_cuenta = stg_bibliotecario.id_cuenta::integer)
                                                  THEN 'id_cuenta ya está en uso por otra cuenta'
    WHEN EXISTS (SELECT 1 FROM cuenta_usuario c
                 WHERE c.login_nombre = 'bib' || lpad(stg_bibliotecario.id_empleado, 3, '0'))
                                                  THEN 'el login generado ya existe'
END;

-- 4. Duplicados dentro del archivo
UPDATE stg_bibliotecario SET motivo = 'id_empleado o id_cuenta repetido en el archivo'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_bibliotecario s2
              WHERE (s2.id_empleado::integer = stg_bibliotecario.id_empleado::integer
                  OR s2.id_cuenta::integer   = stg_bibliotecario.id_cuenta::integer)
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_bibliotecario.linea_csv);

-- 5a. Cuentas (padre)
INSERT INTO cuenta_usuario (id_cuenta, perfil, login_nombre, login_contrasena)
SELECT id_cuenta::integer,
       'bibliotecario'::tipo_perfil,
       'bib' || lpad(id_empleado, 3, '0'),
       '123456'
FROM stg_bibliotecario
WHERE motivo IS NULL;

-- 5b. Bibliotecarios (hijo)
INSERT INTO bibliotecario (id_empleado, id_cuenta, nombre)
SELECT id_empleado::integer, id_cuenta::integer, nombre
FROM stg_bibliotecario
WHERE motivo IS NULL;

-- 6. Rechazos -> bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_bibliotecario
WHERE motivo IS NOT NULL;

COMMIT;

SELECT count(*) FILTER (WHERE motivo IS NULL)     AS bibliotecarios_cargados,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazados
FROM stg_bibliotecario;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_bibliotecario
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
