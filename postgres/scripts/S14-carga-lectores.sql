\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/lectores_semilla.csv
\endif

BEGIN;

-- Forzar la búsqueda en el esquema del laboratorio
SET search_path TO biblioteca;

TRUNCATE stg_linea, stg_lector RESTART IDENTITY;

-- 1. Leer el archivo tal cual: una fila por línea
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir cada línea en sus campos
INSERT INTO stg_lector (linea_csv, contenido, num_campos,
                        documento, nombres, apellidos, correo, telefono)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       lower(trim(split_part(linea, ',', 4))),
       trim(split_part(linea, ',', 5))
FROM stg_linea;

-- 3. Validar
UPDATE stg_lector SET motivo = CASE
    WHEN num_campos <> 5                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 5'
    WHEN documento = ''                           THEN 'documento vacío'
    WHEN documento !~ '^[0-9]{6,15}$'             THEN 'documento no numérico o de longitud inválida'
    WHEN nombres = ''                             THEN 'nombres vacío'
    WHEN apellidos = ''                           THEN 'apellidos vacío'
    WHEN correo = ''                              THEN 'correo vacío'
    WHEN correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'      THEN 'correo mal formado'
    WHEN telefono !~ '^[0-9]{7,15}$'              THEN 'teléfono no numérico o de longitud inválida'
    WHEN EXISTS (SELECT 1 FROM biblioteca.lector l WHERE l.documento = stg_lector.documento::integer)
                                              THEN 'documento ya existe en el sistema'
    WHEN EXISTS (SELECT 1 FROM biblioteca.lector l WHERE l.correo = stg_lector.correo)
                                              THEN 'correo ya existe en el sistema'
END;

-- 4. Duplicados dentro del mismo archivo
UPDATE stg_lector SET motivo = 'documento o correo repetido en el archivo'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_lector s2
              WHERE (s2.documento = stg_lector.documento OR s2.correo = stg_lector.correo)
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_lector.linea_csv);

-- 5a. Crear primero la cuenta de usuario padre
INSERT INTO biblioteca.cuenta_usuario (id_cuenta, perfil, login_nombre, login_contrasena)
SELECT 
    linea_csv AS id_cuenta,
    'lector'::tipo_perfil AS perfil,
    correo AS login_nombre,
    '123456' AS login_contrasena
FROM stg_lector
WHERE motivo IS NULL;

-- 5b. Insertar los lectores referenciando a su cuenta
INSERT INTO biblioteca.lector (documento, id_cuenta, nombre, correo, telefono)
SELECT 
    documento::integer AS documento,
    linea_csv AS id_cuenta,
    nombres || ' ' || apellidos AS nombre,
    correo,
    telefono
FROM stg_lector
WHERE motivo IS NULL;

-- 6. Rechazadas a la bitácora
INSERT INTO biblioteca.rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_lector
WHERE motivo IS NOT NULL;

COMMIT;

-- Resumen de la carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_lector;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_lector
WHERE motivo IS NOT NULL
ORDER BY linea_csv;