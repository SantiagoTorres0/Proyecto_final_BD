-- =============================================================================
-- S14-limpiar-datos.sql — Vacía los DATOS (no el esquema) para recargar de cero
-- =============================================================================
-- Uso:
--   psql -U curso -d curso -f /scripts/S14-limpiar-datos.sql
-- o junto con la carga completa:
--   psql -U curso -d curso -v reiniciar=1 -f /scripts/datos-prueba.sql
--
-- Vacía todo lo que cargan los S14 (incluida la bitácora de rechazos) y
-- reinicia las secuencias. Conserva tablas, tipos, funciones y vistas.
-- (Esquema normalizado: ya no existe la tabla creado_por; se vacían también
--  los catálogos editorial, genero, autor y el puente libro_autor.)
-- DESTRUCTIVO: borra también lo que se haya insertado a mano.
-- =============================================================================

\set ON_ERROR_STOP on
SET search_path TO biblioteca, public;

TRUNCATE prestamo, unidad, libro_autor, libro, autor, genero, editorial,
         bibliotecario, lector, cuenta_usuario,
         rechazo_carga, stg_linea, stg_libro, stg_lector,
         stg_bibliotecario, stg_unidad, stg_prestamo
RESTART IDENTITY;
