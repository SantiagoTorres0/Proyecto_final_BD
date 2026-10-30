-- =============================================================================
-- S14-carga-unidades.sql — unidad.csv -> biblioteca.unidad
-- =============================================================================
-- Uso:
--   psql -U curso -d curso -f /scripts/S14-carga-unidades.sql
--   psql -U curso -d curso -v archivo=/scripts/datos/otro.csv -f /scripts/S14-carga-unidades.sql
--
-- CSV esperado (4 columnas, con encabezado):
--   codigo_libro,codigo_unit,disponibilidad,estado
--
-- Qué arregla respecto al script anterior (datos-prueba.sql, sección A):
--   * stg_unidad se creaba dos veces y la primera versión (con columna
--     `codigo`) no coincidía con el COPY. Ahora hay una sola, en 02_staging.sql.
--   * La línea del CSV se calculaba con row_number() OVER () sin ORDER BY (el
--     orden no está garantizado). Ahora sale de stg_linea.n, que es exacto.
--   * `disponibilidad::boolean` se evaluaba sin comprobar el texto: un valor
--     como 'si' tumbaba TODA la carga. Ahora se valida antes del CAST.
--   * No se detectaban unidades repetidas (PK) ni códigos mal formados.
--   * rechazo_carga.contenido es NOT NULL y se llenaba con codigo_unit, que
--     puede ser nulo: el INSERT de rechazos fallaba. Ahora es la línea cruda.
--
-- Nomenclatura: codigo_unit = 'U-LLL-N' (LLL = libro, N = ejemplar) y el LLL
-- debe coincidir con la columna codigo_libro.
--
-- Reglas de rechazo (primera que falle):
--   columnas <> 4 · libro vacío / no entero · unidad vacía o con formato
--   distinto de U-LLL-N · número de libro del código <> codigo_libro ·
--   disponibilidad o estado distintos de true/false · libro inexistente ·
--   unidad ya existe · disponible Y en mora a la vez · unidad repetida en el
--   archivo.
--
-- Ejecutar DESPUÉS de S14-carga-libros.sql.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/unidad.csv
\endif

SET search_path TO biblioteca, public;

BEGIN;

TRUNCATE stg_linea, stg_unidad RESTART IDENTITY;

-- 1. Leer el archivo tal cual
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir en campos (booleanos en minúscula para comparar fácil)
INSERT INTO stg_unidad (linea_csv, contenido, num_campos,
                        codigo_libro, codigo_unit, disponibilidad, estado)
SELECT n, linea,
       length(linea) - length(replace(linea, ',', '')) + 1,
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       lower(trim(split_part(linea, ',', 3))),
       lower(trim(split_part(linea, ',', 4)))
FROM stg_linea;

-- 3. Validar
UPDATE stg_unidad SET motivo = CASE
    WHEN num_campos <> 4                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 4'
    WHEN codigo_libro = ''                        THEN 'código de libro vacío'
    WHEN codigo_libro !~ '^[0-9]{1,9}$'           THEN 'código de libro no es un entero válido'
    WHEN codigo_unit = ''                         THEN 'código de unidad vacío'
    WHEN codigo_unit !~ '^U-[0-9]{3,}-[0-9]+$'    THEN 'código de unidad no cumple el formato U-LLL-N'
    WHEN split_part(codigo_unit, '-', 2)::integer <> codigo_libro::integer
                                                  THEN 'el libro del código de unidad no coincide con codigo_libro'
    WHEN disponibilidad NOT IN ('true', 'false')  THEN 'disponibilidad debe ser true o false'
    WHEN estado NOT IN ('true', 'false')          THEN 'estado debe ser true o false'
    WHEN NOT EXISTS (SELECT 1 FROM libro l WHERE l.codigo = stg_unidad.codigo_libro::integer)
                                                  THEN 'el libro referenciado no existe en el catálogo'
    WHEN EXISTS (SELECT 1 FROM unidad u WHERE u.codigo_unit = stg_unidad.codigo_unit)
                                                  THEN 'la unidad ya existe en el sistema'
    WHEN disponibilidad = 'true' AND estado = 'true'
                                                  THEN 'violación de regla: una unidad disponible no puede estar en mora (1)'
END;

-- 4. Unidades repetidas dentro del archivo
UPDATE stg_unidad SET motivo = 'unidad repetida en el archivo'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_unidad s2
              WHERE s2.codigo_unit = stg_unidad.codigo_unit
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_unidad.linea_csv);

-- 5. Filas válidas -> unidad (`codigo` lo genera la IDENTITY)
INSERT INTO unidad (codigo_libro, codigo_unit, disponibilidad, estado)
SELECT codigo_libro::integer, codigo_unit, disponibilidad::boolean, estado::boolean
FROM stg_unidad
WHERE motivo IS NULL
ORDER BY linea_csv;

-- 6. Rechazos -> bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_unidad
WHERE motivo IS NOT NULL;

COMMIT;

SELECT count(*) FILTER (WHERE motivo IS NULL)     AS unidades_cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_unidad;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_unidad
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
