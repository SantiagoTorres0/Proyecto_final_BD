#!/bin/sh
# Arranque del contenedor Node.js. Pensado para que el contenedor nunca
# "muera" con un crash-loop confuso si todavía no hay proyecto en
# ./node/proyecto (por ejemplo, en las semanas del curso donde aún no se usa
# Node) — en su lugar, deja el contenedor vivo con instrucciones claras.
set -e

cd /usr/src/app

if [ ! -f package.json ]; then
  echo ""
  echo "=========================================================================="
  echo " No se encontró package.json en entorno-docker/node/proyecto/"
  echo ""
  echo " Coloca ahí el proyecto Node.js de la práctica, o inicia uno nuevo:"
  echo "   docker compose exec node sh"
  echo "   npm init -y"
  echo ""
  echo " Este contenedor seguirá corriendo en espera; no hace falta reiniciarlo,"
  echo " basta con volver a intentar 'docker compose restart node' cuando el"
  echo " proyecto ya tenga package.json."
  echo "=========================================================================="
  echo ""
  exec tail -f /dev/null
fi

echo "Instalando dependencias (npm install)..."
npm install

if grep -q '"dev"[[:space:]]*:' package.json; then
  echo "Iniciando con 'npm run dev'..."
  exec npm run dev
elif grep -q '"start"[[:space:]]*:' package.json; then
  echo "Iniciando con 'npm start'..."
  exec npm start
else
  echo "package.json no define script 'dev' ni 'start'. Contenedor disponible sin arrancar nada."
  echo "Entra con: docker compose exec node sh"
  exec tail -f /dev/null
fi
