\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
\endif

SET search_path TO biblioteca;

BEGIN;

TRUNCATE stg_linea, stg_libro RESTART IDENTITY;

-- 1. Leer el archivo tal cual: una fila por línea
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- Omitir encabezado

-- 2. Partir cada línea en sus campos (como texto)
INSERT INTO stg_libro (linea_csv, contenido, num_campos, isbn, titulo, autor,
                       categoria, anio_publicacion, ejemplares_disponibles)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       trim(split_part(linea, ',', 4)),
       trim(split_part(linea, ',', 5)),
       trim(split_part(linea, ',', 6))
FROM stg_linea;

-- 3. Validar: evaluar reglas en orden
UPDATE stg_libro SET motivo = CASE
    WHEN num_campos <> 6                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
    WHEN isbn = ''                                THEN 'isbn vacío'
    WHEN isbn !~ '^[0-9]{13}$'                    THEN 'isbn no tiene 13 dígitos'
    WHEN titulo = ''                              THEN 'título vacío'
    WHEN autor = ''                               THEN 'autor vacío'
    WHEN categoria = ''                           THEN 'categoría vacía'
    WHEN anio_publicacion !~ '^[0-9]{1,4}$'       THEN 'año no numérico'
    WHEN anio_publicacion::integer NOT BETWEEN 1450 AND 2100
                                                  THEN 'año fuera de rango'
    WHEN ejemplares_disponibles !~ '^-?[0-9]{1,6}$'
                                                  THEN 'ejemplares no numérico'
--WHEN ejemplares_disponibles::integer < 0      THEN 'ejemplares negativo'
    WHEN EXISTS (SELECT 1 FROM libro l WHERE l.isbn = stg_libro.isbn)
                                                  THEN 'isbn ya existe en el catálogo'
END;

-- 4. Detectar duplicados dentro del mismo archivo
UPDATE stg_libro SET motivo = 'isbn repetido en el archivo (línea '
       || (SELECT min(s2.linea_csv) FROM stg_libro s2
           WHERE s2.isbn = stg_libro.isbn AND s2.motivo IS NULL) || ')'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_libro s2
              WHERE s2.isbn = stg_libro.isbn
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_libro.linea_csv);

-- 5. Pasar las filas válidas a la tabla final
INSERT INTO libro (isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles)
SELECT isbn, titulo, autor, categoria,
       anio_publicacion::smallint, ejemplares_disponibles::integer
FROM stg_libro
WHERE motivo IS NULL;

-- 6. Insertar rejected rows en la bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;

COMMIT;

-- Resumen de la carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_libro;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
