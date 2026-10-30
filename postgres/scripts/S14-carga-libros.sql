-- =============================================================================
-- S14-carga-libros.sql — Carga de libros_semilla.csv -> biblioteca.libro
-- =============================================================================
-- Uso:
--   psql -U curso -d curso -f /scripts/S14-carga-libros.sql
--   psql -U curso -d curso -v archivo=/scripts/datos/otro.csv -f /scripts/S14-carga-libros.sql
--
-- CSV esperado (6 columnas, con encabezado):
--   isbn,titulo,autor,categoria,anio_publicacion,ejemplares_disponibles
--
-- Mapeo al esquema:
--   isbn (13 díg.)   -> libro.codigo = últimos 9 dígitos como entero
--   titulo, autor    -> libro.titulo, libro.autor
--   categoria        -> libro.genero
--   (no vienen)      -> edicion = '1ra Edición', editorial = 'Editorial General'
--   anio_publicacion, ejemplares_disponibles: se VALIDAN pero no se guardan
--   (libro no tiene esas columnas; los ejemplares reales viven en `unidad`).
--
-- Reglas de rechazo (se aplica la primera que falle):
--   columnas <> 6 · isbn vacío / sin 13 dígitos · título, autor o categoría
--   vacíos · año no numérico o fuera de 1450..2100 · ejemplares no numérico o
--   negativo · código ya existe en el catálogo · isbn (o sus 9 últimos
--   dígitos) repetido dentro del mismo archivo.
--
-- Es re-ejecutable: lo ya cargado se rechaza como "ya existe", no se duplica.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
\endif

SET search_path TO biblioteca, public;

BEGIN;

TRUNCATE stg_linea, stg_libro RESTART IDENTITY;

-- 1. Leer el archivo tal cual: una fila por línea
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- encabezado

-- 2. Partir cada línea en sus campos (todo como texto)
INSERT INTO stg_libro (linea_csv, contenido, num_campos, isbn, titulo, autor,
                       categoria, anio_publicacion, ejemplares_disponibles)
SELECT n, linea,
       length(linea) - length(replace(linea, ',', '')) + 1,
       trim(split_part(linea, ',', 1)),
       trim(split_part(linea, ',', 2)),
       trim(split_part(linea, ',', 3)),
       trim(split_part(linea, ',', 4)),
       trim(split_part(linea, ',', 5)),
       trim(split_part(linea, ',', 6))
FROM stg_linea;

-- 3. Validar. CASE evalúa en orden y se detiene en la primera regla que falla,
--    por eso los CAST de abajo solo se alcanzan con el formato ya comprobado.
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
    WHEN ejemplares_disponibles::integer < 0      THEN 'ejemplares negativo'
    WHEN EXISTS (SELECT 1 FROM libro l WHERE l.codigo = right(stg_libro.isbn, 9)::integer)
                                                  THEN 'código ya existe en el catálogo'
END;

-- 4. Duplicados dentro del mismo archivo. Se compara por los 9 últimos dígitos
--    (el código real), no solo por isbn completo: dos ISBN distintos con la
--    misma cola chocarían en la PK de libro.
UPDATE stg_libro SET motivo = 'isbn repetido en el archivo (línea '
       || (SELECT min(s2.linea_csv) FROM stg_libro s2
           WHERE right(s2.isbn, 9) = right(stg_libro.isbn, 9) AND s2.motivo IS NULL) || ')'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_libro s2
              WHERE right(s2.isbn, 9) = right(stg_libro.isbn, 9)
                AND s2.motivo IS NULL
                AND s2.linea_csv < stg_libro.linea_csv);

-- 5. Filas válidas -> tabla final
INSERT INTO libro (codigo, autor, titulo, edicion, genero, editorial)
SELECT right(isbn, 9)::integer,
       autor,
       titulo,
       '1ra Edición',          -- el CSV no trae edición
       categoria,              -- categoria (CSV) -> genero (tabla)
       'Editorial General'     -- el CSV no trae editorial
FROM stg_libro
WHERE motivo IS NULL;

-- 6. Rechazos -> bitácora
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;

COMMIT;

-- Resumen de la carga
SELECT count(*) FILTER (WHERE motivo IS NULL)     AS libros_cargados,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazados
FROM stg_libro;

SELECT linea_csv AS linea, motivo, contenido
FROM stg_libro
WHERE motivo IS NOT NULL
ORDER BY linea_csv;
