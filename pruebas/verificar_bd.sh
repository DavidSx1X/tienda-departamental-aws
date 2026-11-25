#!/usr/bin/env bash
# =============================================================================
#  Evidencia de la Entrega 1: ejecutar DENTRO de cada EC2 privado (vía bastión)
#  y tomar captura de la salida.   Uso: ./verificar_bd.sh ordenes|catalogo|carrito
# =============================================================================
set -u
cd "$(dirname "$0")/../servicios/$1" && set -a && source .env && set +a
echo "== $(hostname) · $(date '+%Y-%m-%d %H:%M') · servicio: $1 =="
docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
case "$1" in
  ordenes)
    docker exec ordenes-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -c '\dt tienda.*' \
      -c 'SELECT sku, existencias FROM tienda.inventario ORDER BY sku;' \
      -c 'SELECT cliente_id, orden_id, total, sku, cantidad FROM tienda.v_historial_compras ORDER BY orden_id;' ;;
  catalogo)
    docker exec catalogo-mongo mongosh -u "$MONGO_ROOT_USER" -p "$MONGO_ROOT_PASSWORD" --quiet --eval '
      const c = db.getSiblingDB("catalogo");
      c.getCollectionInfos().forEach(i => print(i.name, "validador:", i.options.validator ? "SI" : "NO",
        "| docs:", c.getCollection(i.name).countDocuments(),
        "| índices:", c.getCollection(i.name).getIndexes().map(x => x.name).join(", ")));
      print(JSON.stringify(c.productos.find({ "categoria.ruta": "linea-blanca", precio: { $lte: NumberDecimal("16000") } },
            { _id: 0, sku: 1, nombre: 1, precio: 1 }).toArray()));'
    docker exec catalogo-redis-cache redis-cli -a "$REDIS_CACHE_PASSWORD" --no-auth-warning INFO server | grep -E 'redis_version|tcp_port'
    docker exec catalogo-redis-cache redis-cli -a "$REDIS_CACHE_PASSWORD" --no-auth-warning CONFIG GET maxmemory-policy ;;
  carrito)
    docker exec carrito-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning PING
    docker exec carrito-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning CONFIG GET appendonly
    grep -v '^#' redis/estructura_claves.redis | grep -v '^$' | head -6 | \
      docker exec -i carrito-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning
    docker exec carrito-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning HGETALL carrito:1
    docker exec carrito-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning TTL carrito:1 ;;
esac
