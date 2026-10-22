\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS biblioteca CASCADE;
CREATE SCHEMA biblioteca;
SET search_path TO biblioteca;

-- Enum de perfiles
CREATE TYPE tipo_perfil AS ENUM (
  'bibliotecario',
  'administrador',
  'lector',
  'auditor'
);

-- Tablas base de tu modelo
CREATE TABLE lector (
  id_lector integer PRIMARY KEY,
  id_cuenta integer UNIQUE NOT NULL,
  nombre varchar NOT NULL,
  correo varchar UNIQUE,
  telefono varchar NOT NULL
);

CREATE TABLE bibliotecario (
  id_empleado integer PRIMARY KEY,
  id_cuenta integer UNIQUE NOT NULL,
  nombre varchar NOT NULL
);

CREATE TABLE libro (
  codigo integer UNIQUE PRIMARY KEY NOT NULL,
  autor varchar NOT NULL,
  titulo varchar NOT NULL,
  edicion varchar NOT NULL,
  genero varchar NOT NULL,
  editorial varchar NOT NULL
);

CREATE TABLE unidad (
  codigo integer NOT NULL,
  codigo_libro integer,
  codigo_unit varchar PRIMARY KEY,
  disponibilidad boolean NOT NULL,
  estado varchar NOT NULL
);

CREATE TABLE prestamo (
  id_prestamo integer PRIMARY KEY,
  fecha_prestamo date NOT NULL,
  codigo_libro varchar NOT NULL,
  id_lector integer NOT NULL,
  codigo varchar NOT NULL, -- <--- Cambiado de integer a varchar para coincidir con unidad.codigo_unit
  id_empleado integer NOT NULL
);

CREATE TABLE usuarios_instancias (
  bibliotecario varchar,
  administrador varchar,
  lector varchar,
  auditor varchar
);

CREATE TABLE cuenta_usuario (
  id_cuenta integer PRIMARY KEY,
  perfil tipo_perfil NOT NULL,
  login_nombre varchar UNIQUE NOT NULL,
  login_contrasena varchar NOT NULL
);

CREATE TABLE creado_por (
  id_empleado integer,
  id_cuenta integer UNIQUE
);

-- Foreign keys de tu modelo
ALTER TABLE cuenta_usuario ADD FOREIGN KEY (id_cuenta) REFERENCES lector (id_cuenta) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE prestamo ADD FOREIGN KEY (id_lector) REFERENCES lector (id_lector) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE prestamo ADD FOREIGN KEY (codigo) REFERENCES unidad (codigo_unit) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE prestamo ADD FOREIGN KEY (id_empleado) REFERENCES bibliotecario (id_empleado) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE unidad ADD FOREIGN KEY (codigo_libro) REFERENCES libro (codigo) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE cuenta_usuario ADD FOREIGN KEY (id_cuenta) REFERENCES bibliotecario (id_cuenta) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE creado_por ADD FOREIGN KEY (id_empleado) REFERENCES bibliotecario (id_empleado) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE cuenta_usuario ADD FOREIGN KEY (id_cuenta) REFERENCES creado_por (id_cuenta) DEFERRABLE INITIALLY IMMEDIATE;

-- Bitácora para el laboratorio S14
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