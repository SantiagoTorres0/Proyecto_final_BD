\set ON_ERROR_STOP on

SET search_path TO biblioteca;

-- Bitácora para el laboratorio S14 (comprobaciones a la hora de cargar los csv en la base de datos)
CREATE TABLE rechazo_carga (
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  archivo text NOT NULL,
  linea integer NOT NULL,
  contenido text NOT NULL,
  motivo text NOT NULL,
  fecha timestamptz NOT NULL DEFAULT now()
);

-- Tablas de paso (staging)
CREATE TABLE stg_linea (
  n integer GENERATED ALWAYS AS IDENTITY,
  linea text
);

CREATE TABLE stg_libro (
  linea_csv integer,
  contenido text,
  num_campos integer,
  isbn text,
  titulo text,
  autor text,
  categoria text,
  anio_publicacion text,
  ejemplares_disponibles text,
  motivo text
);

CREATE TABLE stg_lector (
  linea_csv integer,
  contenido text,
  num_campos integer,
  documento text,
  nombres text,
  apellidos text,
  correo text,
  telefono text,
  motivo text
);