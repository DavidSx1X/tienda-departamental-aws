-- =============================================================================
--  Transacción de compra: confirmar_compra(cliente, renglones, clave)
--
--  Recibe los renglones como JSON, por ejemplo:
--    [{"sku":"REF-LG-GT32","nombre":"Refrigerador LG 11 p3","cantidad":1,"precio":15999.00},
--     {"sku":"CAM-OXF-AZM","nombre":"Camisa Oxford azul M","cantidad":2,"precio":549.00}]
--
--  Garantías:
--   1. Todo o nada: la función corre dentro de UNA transacción. Si un solo SKU
--      no tiene existencias, se lanza una excepción y PostgreSQL deshace todo
--      (no queda orden, ni renglones, ni descuentos parciales).
--   2. Sin inventario negativo con compras simultáneas: el descuento se hace con
--      UPDATE ... SET existencias = existencias - n WHERE existencias >= n.
--      El UPDATE bloquea la fila; la segunda compra espera, y cuando la primera
--      confirma, PostgreSQL vuelve a evaluar el WHERE con el valor nuevo
--      (READ COMMITTED). Si ya no alcanza, el UPDATE afecta 0 filas y la compra
--      se rechaza. El CHECK (existencias >= 0) es la red de seguridad final.
--   3. Sin interbloqueos: los SKU se procesan siempre en orden alfabético, así
--      dos compras con los mismos productos piden los candados en el mismo orden.
--   4. Idempotencia: si llega dos veces la misma clave, se devuelve la orden ya
--      creada en lugar de cobrar dos veces.
--
--  Errores (SQLSTATE) que el servicio traduce a HTTP:
--   P0001 SIN_EXISTENCIAS  -> 409 Conflict
--   P0002 SKU_INEXISTENTE  -> 404 Not Found
--   P0003 CARRITO_VACIO    -> 400 Bad Request
-- =============================================================================
SET search_path TO tienda, public;

CREATE OR REPLACE FUNCTION confirmar_compra(
    p_cliente_id  BIGINT,
    p_renglones   JSONB,
    p_clave       UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = tienda, public
AS $$
DECLARE
    v_orden_id  BIGINT;
    v_total     NUMERIC(12,2);
    v_renglon   RECORD;
    v_num       SMALLINT := 0;
    v_quedan    INTEGER;
BEGIN
    -- Idempotencia: ¿ya se procesó esta compra?
    SELECT orden_id INTO v_orden_id FROM ordenes WHERE clave_idempotencia = p_clave;
    IF FOUND THEN
        RETURN v_orden_id;
    END IF;

    IF p_renglones IS NULL OR jsonb_array_length(p_renglones) = 0 THEN
        RAISE EXCEPTION 'CARRITO_VACIO' USING ERRCODE = 'P0003';
    END IF;

    SELECT SUM((r->>'cantidad')::INT * (r->>'precio')::NUMERIC)
      INTO v_total
      FROM jsonb_array_elements(p_renglones) AS r;

    INSERT INTO ordenes (cliente_id, total, clave_idempotencia)
    VALUES (p_cliente_id, v_total, p_clave)
    RETURNING orden_id INTO v_orden_id;

    FOR v_renglon IN
        SELECT r->>'sku'               AS sku,
               r->>'nombre'            AS nombre,
               (r->>'cantidad')::INT   AS cantidad,
               (r->>'precio')::NUMERIC AS precio
          FROM jsonb_array_elements(p_renglones) AS r
         ORDER BY r->>'sku'                       -- orden fijo => sin deadlocks
    LOOP
        UPDATE inventario
           SET existencias    = existencias - v_renglon.cantidad,
               actualizado_en = now()
         WHERE sku = v_renglon.sku
           AND existencias >= v_renglon.cantidad
        RETURNING existencias INTO v_quedan;

        IF NOT FOUND THEN
            IF NOT EXISTS (SELECT 1 FROM inventario WHERE sku = v_renglon.sku) THEN
                RAISE EXCEPTION 'SKU_INEXISTENTE: %', v_renglon.sku USING ERRCODE = 'P0002';
            END IF;
            RAISE EXCEPTION 'SIN_EXISTENCIAS: %', v_renglon.sku USING ERRCODE = 'P0001';
        END IF;

        v_num := v_num + 1;
        INSERT INTO orden_detalle (orden_id, renglon, sku, nombre_producto, cantidad, precio_unitario)
        VALUES (v_orden_id, v_num, v_renglon.sku, v_renglon.nombre, v_renglon.cantidad, v_renglon.precio);

        INSERT INTO movimientos_inventario (sku, tipo, cantidad, orden_id)
        VALUES (v_renglon.sku, 'SALIDA', v_renglon.cantidad, v_orden_id);
    END LOOP;

    RETURN v_orden_id;
END;
$$;

COMMENT ON FUNCTION confirmar_compra(BIGINT, JSONB, UUID) IS
  'Registra la orden y descuenta inventario de forma atómica; rechaza la compra completa si falta existencia.';

-- -----------------------------------------------------------------------------
-- (Extra) Recomendaciones: "quienes compraron esto también compraron"
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION recomendaciones(p_sku VARCHAR, p_limite INT DEFAULT 5)
RETURNS TABLE (sku VARCHAR, veces BIGINT)
LANGUAGE sql STABLE
SET search_path = tienda, public
AS $$
    SELECT otro.sku, COUNT(DISTINCT otro.orden_id) AS veces
      FROM orden_detalle base
      JOIN orden_detalle otro
        ON otro.orden_id = base.orden_id AND otro.sku <> base.sku
     WHERE base.sku = p_sku
     GROUP BY otro.sku
     ORDER BY veces DESC, otro.sku
     LIMIT p_limite;
$$;
