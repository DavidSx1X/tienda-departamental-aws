-- =============================================================================
--  Servicio de órdenes e inventario — Esquema relacional (PostgreSQL 16)
--  Proyecto Final: Tienda Departamental · Bases de Datos en la Nube · UPV
--  Responsable de la capa: Rol 2 (capa relacional)
--
--  Este script se ejecuta automáticamente al crear el contenedor de PostgreSQL
--  (carpeta /docker-entrypoint-initdb.d). También puede correrse a mano:
--      psql -U tienda -d ordenes -f 01_esquema.sql
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS tienda;
SET search_path TO tienda, public;
-- Que las conexiones del servicio encuentren las tablas sin prefijo
DO $$ BEGIN EXECUTE format('ALTER DATABASE %I SET search_path = tienda, public', current_database()); END $$;

-- -----------------------------------------------------------------------------
-- Clientes. Sólo los datos que necesita la compra y el historial.
-- La sesión del cliente NO vive aquí: vive en Redis (servicio de carrito).
-- -----------------------------------------------------------------------------
CREATE TABLE clientes (
    cliente_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre         VARCHAR(120) NOT NULL,
    email          VARCHAR(160) NOT NULL,
    password_hash  VARCHAR(100) NOT NULL,              -- bcrypt; nunca texto plano
    telefono       VARCHAR(20),
    creado_en      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_clientes_email UNIQUE (email),
    CONSTRAINT ck_clientes_email CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

-- -----------------------------------------------------------------------------
-- Inventario. Una fila por SKU. El SKU es el identificador común con el
-- catálogo (MongoDB), pero NO hay llave foránea entre bases: cada servicio es
-- dueño de sus datos y se comunican por API.
-- El CHECK (existencias >= 0) es la última línea de defensa: aunque la
-- aplicación fallara, la base de datos nunca acepta inventario negativo.
-- -----------------------------------------------------------------------------
CREATE TABLE inventario (
    sku              VARCHAR(30)  PRIMARY KEY,
    existencias      INTEGER      NOT NULL DEFAULT 0,
    stock_minimo     INTEGER      NOT NULL DEFAULT 5,
    actualizado_en   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_inventario_existencias CHECK (existencias >= 0),
    CONSTRAINT ck_inventario_minimo      CHECK (stock_minimo >= 0),
    CONSTRAINT ck_inventario_sku         CHECK (sku ~ '^[A-Z0-9-]{3,30}$')
);

-- -----------------------------------------------------------------------------
-- Órdenes (encabezado). clave_idempotencia evita que un reintento de red
-- (doble clic, timeout del cliente) genere dos órdenes por la misma compra.
-- -----------------------------------------------------------------------------
CREATE TABLE ordenes (
    orden_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id          BIGINT        NOT NULL REFERENCES clientes (cliente_id),
    fecha               TIMESTAMPTZ   NOT NULL DEFAULT now(),
    estado              VARCHAR(12)   NOT NULL DEFAULT 'CONFIRMADA',
    total               NUMERIC(12,2) NOT NULL,
    clave_idempotencia  UUID          NOT NULL,
    CONSTRAINT ck_ordenes_estado CHECK (estado IN ('CONFIRMADA', 'CANCELADA', 'ENTREGADA')),
    CONSTRAINT ck_ordenes_total  CHECK (total >= 0),
    CONSTRAINT uq_ordenes_idempotencia UNIQUE (clave_idempotencia)
);

-- -----------------------------------------------------------------------------
-- Renglones de la orden. Guardan una "foto" (snapshot) del nombre y del precio
-- al momento de la compra: si mañana el catálogo cambia el precio, el
-- historial del cliente sigue mostrando lo que realmente pagó.
-- -----------------------------------------------------------------------------
CREATE TABLE orden_detalle (
    orden_id         BIGINT        NOT NULL REFERENCES ordenes (orden_id) ON DELETE CASCADE,
    renglon          SMALLINT      NOT NULL,
    sku              VARCHAR(30)   NOT NULL REFERENCES inventario (sku),
    nombre_producto  VARCHAR(160)  NOT NULL,
    cantidad         INTEGER       NOT NULL,
    precio_unitario  NUMERIC(12,2) NOT NULL,
    subtotal         NUMERIC(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    PRIMARY KEY (orden_id, renglon),
    CONSTRAINT uq_detalle_sku        UNIQUE (orden_id, sku),
    CONSTRAINT ck_detalle_cantidad   CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_precio     CHECK (precio_unitario >= 0)
);

-- -----------------------------------------------------------------------------
-- Bitácora de movimientos de inventario (entradas por reabasto, salidas por
-- venta). Permite auditar por qué cambió una existencia.
-- -----------------------------------------------------------------------------
CREATE TABLE movimientos_inventario (
    movimiento_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku            VARCHAR(30)  NOT NULL REFERENCES inventario (sku),
    tipo           VARCHAR(10)  NOT NULL,
    cantidad       INTEGER      NOT NULL,
    orden_id       BIGINT       REFERENCES ordenes (orden_id),
    fecha          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_mov_tipo     CHECK (tipo IN ('ENTRADA', 'SALIDA', 'AJUSTE')),
    CONSTRAINT ck_mov_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_mov_salida_con_orden CHECK (tipo <> 'SALIDA' OR orden_id IS NOT NULL)
);

-- -----------------------------------------------------------------------------
-- Índices que respaldan las consultas del servicio
-- -----------------------------------------------------------------------------
CREATE INDEX ix_ordenes_cliente_fecha ON ordenes (cliente_id, fecha DESC);     -- historial de compras
CREATE INDEX ix_detalle_sku           ON orden_detalle (sku);                  -- recomendaciones (extra)
CREATE INDEX ix_mov_sku_fecha         ON movimientos_inventario (sku, fecha DESC);
CREATE INDEX ix_inventario_bajo       ON inventario (sku) WHERE existencias <= stock_minimo;

-- -----------------------------------------------------------------------------
-- Vista: historial de compras de un cliente (una fila por renglón)
-- -----------------------------------------------------------------------------
CREATE VIEW v_historial_compras AS
SELECT o.cliente_id, o.orden_id, o.fecha, o.estado, o.total,
       d.renglon, d.sku, d.nombre_producto, d.cantidad, d.precio_unitario, d.subtotal
FROM ordenes o
JOIN orden_detalle d USING (orden_id);
