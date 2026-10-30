-- =============================================================================
-- datos-prueba.sql — Carga COMPLETA de los CSV semilla, en el orden correcto
-- =============================================================================
-- Uso (la base ya debe tener 01_esquema.sql y 02_staging.sql aplicados):
--
--   docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
--
--   # recarga desde cero (borra los datos actuales):
--   docker compose exec postgres psql -U curso -d curso -v reiniciar=1 -f /scripts/datos-prueba.sql
--
--   # CSV en otra carpeta del contenedor:
--   ... psql -U curso -d curso -v dir=/otra/ruta -f /scripts/datos-prueba.sql
--
-- Orden (cada paso depende de los anteriores por las llaves foráneas):
--
--   1. libros          (libro)
--   2. lectores        (cuenta_usuario + lector)           ids de cuenta 1..20
--   3. bibliotecarios  (cuenta_usuario + bibliotecario)    ids de cuenta 21..25
--   4. unidades        (unidad)            necesita libros
--   5. préstamos       (prestamo)          necesita lectores, bibliotecarios, unidades
--
-- Cada paso es su propio script S14-carga-*.sql con su propia transacción:
-- si uno falla por error de SQL, los anteriores quedan confirmados y los
-- siguientes no corren (ON_ERROR_STOP). Las filas con DATOS malos nunca abortan
-- nada: se registran en biblioteca.rechazo_carga.
--
-- Resultado esperado con los CSV semilla (todos limpios): 0 rechazos y
--   libros 32 · lectores 20 · bibliotecarios 5 · unidades 64 · préstamos 20
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?dir}
\else
    \set dir /scripts/datos
\endif

\if :{?reiniciar}
    \echo '>> Reiniciando datos...'
    \ir S14-limpiar-datos.sql
\endif

\echo
\echo '>> 1/5 Libros'
\set archivo :dir/libros_semilla.csv
\ir S14-carga-libros.sql

\echo
\echo '>> 2/5 Lectores'
\set archivo :dir/lectores_semilla.csv
\ir S14-carga-lectores.sql

\echo
\echo '>> 3/5 Bibliotecarios'
\set archivo :dir/bibliotecario.csv
\ir S14-carga-bibliotecarios.sql

\echo
\echo '>> 4/5 Unidades'
\set archivo :dir/unidad.csv
\ir S14-carga-unidades.sql

\echo
\echo '>> 5/5 Préstamos'
\set archivo :dir/prestamo.csv
\ir S14-carga-prestamos.sql

-- -----------------------------------------------------------------------------
-- Resumen de control
-- -----------------------------------------------------------------------------
SET search_path TO biblioteca, public;

\echo
\echo '=== Filas en las tablas finales ==='
SELECT 'libro' AS tabla, count(*) AS filas FROM libro
UNION ALL SELECT 'cuenta_usuario',  count(*) FROM cuenta_usuario
UNION ALL SELECT 'lector',          count(*) FROM lector
UNION ALL SELECT 'bibliotecario',   count(*) FROM bibliotecario
UNION ALL SELECT 'unidad',          count(*) FROM unidad
UNION ALL SELECT 'prestamo',        count(*) FROM prestamo;

\echo
\echo '=== Rechazos acumulados en la bitácora (vacío = todo cargó) ==='
SELECT archivo, count(*) AS rechazos
FROM rechazo_carga
GROUP BY archivo
ORDER BY archivo;
