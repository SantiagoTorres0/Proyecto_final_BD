\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS biblioteca CASCADE;
CREATE SCHEMA biblioteca;
SET search_path TO biblioteca;

-- Tablas finales
CREATE TABLE libro (
    isbn                    varchar(13)   PRIMARY KEY CHECK (isbn ~ '^[0-9]{13}$'),
    titulo                  varchar(200)  NOT NULL CHECK (titulo <> ''),
    autor                   varchar(120)  NOT NULL CHECK (autor <> ''),
    categoria               varchar(40)   NOT NULL CHECK (categoria <> ''),
    anio_publicacion        smallint      NOT NULL CHECK (anio_publicacion BETWEEN 1450 AND 2100),
    ejemplares_disponibles  integer       NOT NULL CHECK (ejemplares_disponibles >= 0)
);

CREATE TABLE lector (
    documento  varchar(15)   PRIMARY KEY CHECK (documento ~ '^[0-9]{6,15}$'),
    nombres    varchar(80)   NOT NULL CHECK (nombres <> ''),
    apellidos  varchar(80)   NOT NULL CHECK (apellidos <> ''),
    correo     varchar(120)  NOT NULL UNIQUE CHECK (correo ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'),
    telefono   varchar(15)   NOT NULL CHECK (telefono ~ '^[0-9]{7,15}$')
);

-- Bitácora de errores
CREATE TABLE rechazo_carga (
    id         integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    archivo    text         NOT NULL,
    linea      integer      NOT NULL,
    contenido  text         NOT NULL,
    motivo     text         NOT NULL,
    fecha      timestamptz  NOT NULL DEFAULT now()
);

-- Tablas de paso (staging)
CREATE TABLE stg_linea (
    n      integer  GENERATED ALWAYS AS IDENTITY,
    linea  text
);

CREATE TABLE stg_libro (
    linea_csv               integer,
    contenido               text,
    num_campos              integer,
    isbn                    text,
    titulo                  text,
    autor                   text,
    categoria               text,
    anio_publicacion        text,
    ejemplares_disponibles  text,
    motivo                  text
);

CREATE TABLE stg_lector (
    linea_csv   integer,
    contenido   text,
    num_campos  integer,
    documento   text,
    nombres     text,
    apellidos   text,
    correo      text,
    telefono    text,
    motivo      text
);
