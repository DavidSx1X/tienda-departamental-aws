#!/usr/bin/env bash
# =============================================================================
#  Prueba de concurrencia a nivel base de datos (antes de tener la API).
#  Dos compras simultáneas de la ÚLTIMA pieza de SAR-TFL-24.
#  La compra A toma el candado y espera 3 s antes de confirmar; la compra B
#  arranca mientras A sigue abierta. Resultado esperado: A confirma, B es
#  rechazada con SIN_EXISTENCIAS y el inventario queda en 0 (nunca en -1).
#
#  Uso (desde el bastión, con túnel al EC2 de órdenes, o dentro del EC2):
#     PGHOST=localhost PGPORT=5432 PGUSER=tienda PGDATABASE=ordenes ./prueba_concurrencia_bd.sh
# =============================================================================
set -u
SKU=${SKU:-SAR-TFL-24}
PSQL="psql -X -q -v ON_ERROR_STOP=1"

$PSQL -c "UPDATE tienda.inventario SET existencias = 1 WHERE sku = '$SKU';"
echo "Existencias iniciales: $($PSQL -tA -c "SELECT existencias FROM tienda.inventario WHERE sku='$SKU'")"

RENGLON="[{\"sku\":\"$SKU\",\"nombre\":\"Sartén T-fal 24 cm\",\"cantidad\":1,\"precio\":459.00}]"

compra () {   # $1 = etiqueta, $2 = segundos de espera dentro de la transacción, $3 = cliente
  local inicio=$(date +%s.%N)
  local salida
  salida=$($PSQL -tA 2>&1 <<SQL
BEGIN;
SELECT 'orden ' || tienda.confirmar_compra($3, '$RENGLON', gen_random_uuid());
SELECT pg_sleep($2);
COMMIT;
SQL
)
  local fin=$(date +%s.%N)
  printf "Compra %s (cliente %s): %s  [%.2f s]\n" "$1" "$3" "$(echo "$salida" | grep -E 'orden|ERROR' | head -1)" "$(echo "$fin - $inicio" | bc)"
}

compra A 3 1 &
sleep 0.5
compra B 0 2 &
wait

echo "Existencias finales: $($PSQL -tA -c "SELECT existencias FROM tienda.inventario WHERE sku='$SKU'")"
echo "Órdenes con $SKU:    $($PSQL -tA -c "SELECT count(*) FROM tienda.orden_detalle WHERE sku='$SKU'")"
