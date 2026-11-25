#!/bin/bash
# =============================================================================
#  Despliega las bases de datos en las 3 instancias privadas desde CloudShell.
#  Requiere ~/.ssh/config con los alias gw, catalogo, carrito y ordenes
#  (ProxyJump por el bastión). Genera un .env con contraseñas aleatorias
#  por servicio la primera vez (los .env NUNCA se suben al repositorio).
# =============================================================================
cd "$(dirname "$0")/.."
for s in catalogo carrito ordenes; do
  [ -f servicios/$s/.env ] || python3 -c "import secrets,re
for l in open('servicios/$s/.env_example').read().splitlines(): print(l+secrets.token_hex(12) if re.fullmatch(r'[A-Z_]*PASSWORD=',l) else l)" > servicios/$s/.env
done
cd .. && tar czf /tmp/td.tgz --exclude='*.png' --exclude='salida_*' "$(basename "$OLDPWD")"
for s in catalogo carrito ordenes; do
  echo "===== $s"
  scp -q /tmp/td.tgz $s:/tmp/td.tgz && ssh $s "tar xzf /tmp/td.tgz -C ~ && chmod +x ~/tienda-departamental/pruebas/*.sh ~/tienda-departamental/servicios/ordenes/db/init/*.sh && cd ~/tienda-departamental/servicios/$s && docker compose up -d 2>&1 | tail -4"
done
