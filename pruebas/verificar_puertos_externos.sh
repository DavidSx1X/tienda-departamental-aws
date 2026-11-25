#!/usr/bin/env bash
# Ejecutar desde la laptop (FUERA de AWS). Demuestra que sólo el puerto 80 está expuesto.
# Uso: ./verificar_puertos_externos.sh <IP_PUBLICA_GATEWAY>
IP=${1:?IP pública del gateway}
for p in 80 22 3001 3002 3003 5432 27017 6379; do
  if timeout 3 bash -c "</dev/tcp/$IP/$p" 2>/dev/null; then echo "puerto $p: ABIERTO"; else echo "puerto $p: cerrado/filtrado"; fi
done
echo; curl -s "http://$IP/health"; echo
