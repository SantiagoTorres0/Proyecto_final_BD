# Entorno Docker del curso — PostgreSQL + pgAdmin + Node.js

Un único `docker-compose.yml` para **todas las prácticas del semestre y el
proyecto final**. No se clona ni se copia por práctica: se levanta una vez y
se reutiliza, cambiando solo el contenido de tres carpetas. Pensado para que
enseñar/aprender sea fácil, no para producción (credenciales de ejemplo,
todo en `localhost`, sin TLS).

## Qué trae

| Servicio | Imagen | Para qué | Puerto en tu máquina |
|---|---|---|---|
| `postgres` | `postgres:16` | El motor relacional del curso | `localhost:5432` |
| `pgadmin` | `dpage/pgadmin4` | Administración gráfica de Postgres | `localhost:5050` |
| `node` | `node:20-alpine` | Corre el proyecto Node.js de la práctica/proyecto | `localhost:3000` |

## Estructura (lo único que necesitas tocar)

```
entorno-docker/
├── docker-compose.yml
├── .env.example              # copiar a .env si quieres cambiar credenciales/puertos
├── postgres/
│   ├── init/                 # scripts que corren UNA vez (base vacía) — esquema + datos semilla
│   ├── scripts/               # scripts sueltos para correr a mano cuando quieras
│   └── data/                  # ahí vive la base de datos en tu disco (no tocar a mano)
├── pgadmin/
│   ├── servers.json           # conexión a "postgres" precargada en pgAdmin
│   └── data/                  # configuración/sesión de pgAdmin (persiste)
└── node/
    ├── docker-entrypoint.sh
    └── proyecto/               # AQUÍ va el código de tu práctica o proyecto final
```

Cada subcarpeta tiene su propio `README.md` con el detalle.

## Requisitos

- Docker Desktop (Windows/Mac) o Docker Engine + Docker Compose Plugin (Linux).
- Verifica con: `docker compose version`.

## Primer arranque

```bash
cd entorno-docker
docker compose up -d
```

Eso levanta los tres servicios. La primera vez, Postgres ejecuta los
scripts de `postgres/init/` (si hay alguno) para crear el esquema inicial.

- **PostgreSQL:** `localhost:5432`, usuario/clave `curso`, base `curso`.
- **pgAdmin:** abre `http://localhost:5050` — el servidor "Curso -
  PostgreSQL" ya está precargado, solo pide la contraseña de Postgres
  (`curso`) la primera vez y luego la recuerda.
- **Node:** si `node/proyecto/` tiene un `package.json`, tu app queda
  disponible en `http://localhost:3000` (o el puerto que uses).

Solo necesitas Postgres y pgAdmin encendidos (por ejemplo, en las semanas de
SQL puro, sin API)? Levanta solo esos dos:

```bash
docker compose up -d postgres pgadmin
```

## Flujo de trabajo típico por práctica

**Prácticas de SQL/modelado (solo Postgres + pgAdmin):**

1. Reemplaza los archivos de `postgres/init/` por el `.sql` de la práctica
   (esquema + datos semilla).
2. Si ya habías usado el entorno antes, borra los datos para que el init
   vuelva a correr: `docker compose down && rm -rf postgres/data/*`.
3. `docker compose up -d postgres pgadmin` y trabaja desde pgAdmin, o por
   línea de comandos: `docker compose exec postgres psql -U curso -d curso`.

**Prácticas de API REST / proyecto final (Postgres + Node):**

1. Coloca el proyecto Node.js en `node/proyecto/` (ver su README).
2. `docker compose up -d`.
3. Edita el código con tu editor normal en tu máquina — el contenedor ve los
   cambios al instante; si usas `nodemon` en el script `dev`, la app se
   reinicia sola.

## Comandos que vas a usar seguido

```bash
docker compose up -d              # levantar todo en segundo plano
docker compose ps                 # ver qué está corriendo
docker compose logs -f node       # ver logs en vivo de un servicio (postgres | pgadmin | node)
docker compose exec node sh       # abrir una terminal dentro del contenedor de Node
docker compose exec postgres psql -U curso -d curso   # abrir psql
docker compose restart node       # reiniciar Node (p. ej. después de crear package.json)
docker compose down               # apagar todo (los datos NO se borran)
```

## Cómo empezar de cero (borrar todo y volver a construir)

```bash
docker compose down
rm -rf postgres/data/* pgadmin/data/*
docker compose up -d
```

En Linux, si `rm -rf postgres/data/*` da "Permission denied": los archivos
quedaron con dueño del usuario del contenedor. Usa `sudo rm -rf
postgres/data/*`, o bórralos desde dentro de Docker:

```bash
docker compose run --rm postgres sh -c "rm -rf /var/lib/postgresql/data/*"
```

## Preguntas frecuentes

**¿Pierdo mis datos si apago el computador?**
No. `postgres/data/` y `pgadmin/data/` son carpetas normales en tu disco
(bind mounts), no algo interno de Docker — sobreviven a `docker compose
down`, reinicios y apagones. Solo se pierden si las borras a propósito (ver
arriba) o corres `docker compose down -v`.

**¿Puedo usar el mismo entorno para el proyecto final?**
Sí, es justo la idea: mismas tres carpetas, mismo `docker-compose.yml`.
Cambia el contenido de `postgres/init/` y `node/proyecto/` por los del
proyecto y sigue igual.

**¿Cómo cambio el puerto porque ya tengo algo corriendo en 5432/5050/3000?**
Copia `.env.example` a `.env` y cambia `POSTGRES_PORT`, `PGADMIN_PORT` o
`NODE_PORT`. No hace falta tocar `docker-compose.yml`.

**¿Cómo conecto mi código Node a Postgres?**
Desde dentro del contenedor, el host de la base es `postgres` (nombre del
servicio), no `localhost`. Con la librería `pg`, `new Pool()` sin
argumentos ya funciona: toma host/usuario/clave/base de las variables de
entorno que el `docker-compose.yml` le pasa al contenedor `node`.
