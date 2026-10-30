-- =============================================================================
-- S14-carga-lectores.sql — Carga de lectores_semilla.csv -> cuenta_usuario + lector
-- =============================================================================
-- Uso:
--   psql -U curso -d curso -f /scripts/S14-carga-lectores.sql
--   psql -U curso -d curso -v archivo=/scripts/datos/otro.csv -f /scripts/S14-carga-lectores.sql
--
-- CSV esperado (5 columnas, con encabezado):
--   documento,nombres,apellidos,correo,telefono
--
-- Cada lector válido crea DOS filas, en este orden (la FK lo exige):
--   1. cuenta_usuario: perfil 'lector', login = correo, contraseña inicial
--      '123456' (ver nota de seguridad en el README).
--   2. lector: nombre = nombres || ' ' || apellidos.
--
-- id_cuenta: se asigna como (mayor id_cuenta existente) + posición dentro de
-- las filas válidas. ANTES se usaba el número de línea del CSV, lo que chocaba
-- con los id_cuenta que trae bibliotecario.csv (21..25) y no admitía recargas.
-- Por eso este script debe correr ANTES que el de bibliotecarios: en una base
-- vacía los lectores toman 1..20 y los bibliotecarios conservan 21..25.
--
-- Reglas de rechazo (primera que falle):
--   columnas <> 5 · documento vacío / no numérico / fuera de 6..15 dígitos ·
--   nombres, apellidos o correo vacíos · correo mal formado · teléfono no
--   numérico (7..15 dígitos) · documento o correo ya existen · correo ya usado
--   como login · documento o correo repetido en el archivo.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/lectores_semilla.csv
\endif

-- Trabajar EXCLUSIVAMENTE en el esquema biblioteca
SET search_path TO biblioteca, public;

BEGIN;

TRUNCATE stg_linea, stg_lector RESTART IDENTITY;

-- 1. Leer el archivo tal cual: una fila por línea
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir cada línea en sus campos
INSERT INTO stg_lector (linea_csv, contenido, num_campos,
                        documento, nombres, apellidos, correo, telefono)
SELECT n, linea,
       length(linea) - length(replace(linea, ',', '')) + 1,
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       lower(trim(split_part(linea, ',', 4))),
       trim(split_part(linea, ',', 5))
FROM stg_linea;

-- 3. Validaciones estructurales y de existencia
UPDATE stg_lector SET motivo = CASE
    WHEN num_campos <> 5                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 5'
    WHEN documento = ''                           THEN 'documento vacío'
    WHEN documento !~ '^[0-9]{6,15}$'             THEN 'documento no numérico o de longitud inválida'
    WHEN nombres = ''                             THEN 'nombres vacío'
    WHEN apellidos = ''                           THEN 'apellidos vacío'
    WHEN correo = ''                              THEN 'correo vacío'
    WHEN correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'      THEN 'correo mal formado'
    WHEN telefono !~ '^[0-9]{7,15}$'              THEN 'teléfono no numérico o de longitud inválida'
    WHEN EXISTS (SELECT 1 FROM biblioteca.lector l WHERE l.documento = stg_lector.documento::bigint)
                                                  THEN 'documento ya existe en el sistema'
    WHEN EXISTS (SELECT 1 FROM biblioteca.lector l WHERE l.correo = stg_lector.correo)
                                                  THEN 'correo ya existe en el sistema'
    WHEN EXISTS (SELECT 1 FROM biblioteca.cuenta_usuario c WHERE c.login_nombre = stg_lector.correo)
                                                  THEN 'correo ya está en uso como login de otra cuenta'
END;

-- 4. Duplicados dentro del mismo archivo (gana la primera aparición)
UPDATE stg_lector SET motivo = 'documento o correo repetido en el archivo'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_lector s2
              WHERE (s2.documento = stg_lector.documento OR s2.correo = stg_lector.correo)
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_lector.linea_csv);

-- 5a. Cuentas de usuario (padre). id_cuenta = máximo existente + posición.
INSERT INTO cuenta_usuario (id_cuenta, perfil, login_nombre, login_contrasena)
SELECT (SELECT coalesce(max(id_cuenta), 0) FROM cuenta_usuario)
         + row_number() OVER (ORDER BY linea_csv),
       'lector'::tipo_perfil,
       correo,
       '123456'
FROM stg_lector
WHERE motivo IS NULL;

-- 5b. Lectores (hijo): se enlazan con su cuenta por login_nombre = correo,
--     que es único, así no dependemos de recalcular el id.
INSERT INTO lector (documento, id_cuenta, nombre, correo, telefono)
SELECT s.documento::bigint,
       c.id_cuenta,
       s.nombres || ' ' || s.apellidos,
       s.correo,
       s.telefono
FROM stg_lector s
JOIN cuenta_usuario c ON c.login_nombre = s.correo
WHERE s.motivo IS NULL;

-- 6. Rechazos -> bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_lector
WHERE motivo IS NOT NULL;

COMMIT;

-- Resumen de la carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS lectores_cargados,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazados
FROM stg_lector;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
