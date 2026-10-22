# `node/proyecto/`

Aquí va el código del proyecto Node.js que quieres correr (el de una
práctica, o el proyecto final). El contenedor `node` monta esta carpeta
completa como su directorio de trabajo: lo que edites aquí en tu editor de
texto normal se refleja al instante dentro del contenedor.

- Si hay `package.json`, al levantar el servicio se corre `npm install`
  automáticamente y luego el script `dev` (o `start`, si no existe `dev`).
- Si esta carpeta está vacía, el contenedor queda esperando con
  instrucciones — no falla ni se reinicia en bucle.
- La base de datos se alcanza desde el código como `postgres` (no
  `localhost`): con la librería `pg`, `new Pool()` ya toma host, usuario,
  contraseña y base de datos de las variables de entorno del contenedor, sin
  que tengas que escribirlas en el código.

## Empezar un proyecto nuevo

```bash
docker compose up -d          # levanta postgres, pgadmin y node
docker compose exec node sh   # entra al contenedor
npm init -y
npm install express pg
# ... escribe tu código ...
exit
docker compose restart node   # ahora sí encuentra package.json y arranca
```
