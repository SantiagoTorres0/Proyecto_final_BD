ALTER TABLE biblioteca.prestamo
    ADD COLUMN IF NOT EXISTS fecha_devolucion date;
