-- =============================================================================
-- S14-carga-devoluciones.sql: devoluciones.csv -> prestamo.fecha_devolucion
-- =============================================================================
-- Uso:
--   psql -U curso -d curso -f /scripts/S14-carga-devoluciones.sql
--   psql -U curso -d curso -v archivo=/scripts/datos/otro.csv -f /scripts/S14-carga-devoluciones.sql
--
-- CSV esperado (2 columnas, con encabezado):
--   id_prestamo,fecha_devolucion
--
-- Requisitos:
--   * agregar-fecha-devolucion.sql aplicado (la columna debe existir).
--   * Préstamos ya cargados por S14-carga-prestamos.sql.
--
-- Reglas de rechazo (primera que falle):
--   columnas <> 2 · id_prestamo vacío o inválido · fecha vacía o inválida ·
--   fecha futura · préstamo inexistente · préstamo que ya tiene devolución ·
--   devolución anterior al préstamo · id_prestamo repetido en el archivo.
--
-- Los préstamos que no aparecen en el CSV quedan abiertos (fecha_devolucion NULL).
-- Staging en una tabla temporal: no requiere cambios en el esquema.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/devoluciones.csv
\endif

SET search_path TO biblioteca, public;

BEGIN;

DROP TABLE IF EXISTS pg_temp.tmp_devolucion;
CREATE TEMP TABLE tmp_devolucion (
    linea_csv        integer,
    contenido        text,
    num_campos       integer,
    id_prestamo      text,
    fecha_devolucion text,
    motivo           text
);

-- 1. Leer el archivo tal cual
TRUNCATE stg_linea RESTART IDENTITY;
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir en campos
INSERT INTO tmp_devolucion (linea_csv, contenido, num_campos, id_prestamo, fecha_devolucion)
SELECT n, linea,
       length(linea) - length(replace(linea, ',', '')) + 1,
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2))
FROM stg_linea;

-- 3. Validar
UPDATE tmp_devolucion SET motivo = CASE
    WHEN num_campos <> 2                       THEN 'tiene ' || num_campos || ' columnas, se esperaban 2'
    WHEN id_prestamo !~ '^[0-9]{1,9}$'         THEN 'id_prestamo vacío o no es un entero válido'
    WHEN NOT es_fecha(fecha_devolucion)        THEN 'fecha_devolucion vacía o no es una fecha válida (AAAA-MM-DD)'
    WHEN fecha_devolucion::date > CURRENT_DATE THEN 'la fecha de devolución es futura'
    WHEN NOT EXISTS (SELECT 1 FROM prestamo p
                     WHERE p.id_prestamo = tmp_devolucion.id_prestamo::integer)
                                               THEN 'el préstamo no existe'
    WHEN EXISTS (SELECT 1 FROM prestamo p
                 WHERE p.id_prestamo = tmp_devolucion.id_prestamo::integer
                   AND p.fecha_devolucion IS NOT NULL)
                                               THEN 'el préstamo ya tiene devolución registrada'
    WHEN fecha_devolucion::date < (SELECT p.fecha_prestamo FROM prestamo p
                                   WHERE p.id_prestamo = tmp_devolucion.id_prestamo::integer)
                                               THEN 'la devolución es anterior al préstamo'
END;

-- 4. id_prestamo repetido dentro del archivo
UPDATE tmp_devolucion SET motivo = 'id_prestamo repetido en el archivo'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM tmp_devolucion t2
              WHERE t2.id_prestamo = tmp_devolucion.id_prestamo
                AND t2.motivo IS NULL
                AND t2.linea_csv < tmp_devolucion.linea_csv);

-- 5. Devoluciones válidas -> prestamo
UPDATE prestamo p
SET fecha_devolucion = v.fecha
FROM (SELECT id_prestamo::integer AS id, fecha_devolucion::date AS fecha
      FROM tmp_devolucion
      WHERE motivo IS NULL) v
WHERE p.id_prestamo = v.id
  AND p.fecha_devolucion IS NULL;

-- 6. Rechazos -> bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM tmp_devolucion
WHERE motivo IS NOT NULL;

COMMIT;

SELECT count(*) FILTER (WHERE motivo IS NULL)     AS devoluciones_cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM tmp_devolucion;

SELECT linea_csv AS linea, motivo, contenido
FROM tmp_devolucion
WHERE motivo IS NOT NULL
ORDER BY linea_csv;

DROP TABLE pg_temp.tmp_devolucion;