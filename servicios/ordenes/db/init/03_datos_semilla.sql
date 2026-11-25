-- =============================================================================
--  Datos de prueba del servicio de órdenes e inventario
--  Los SKU coinciden con los productos del catálogo (MongoDB).
--  Las contraseñas son hashes bcrypt de ejemplo ("Demo2026!"); no son reales.
-- =============================================================================
SET search_path TO tienda, public;

INSERT INTO clientes (nombre, email, password_hash, telefono) VALUES
 ('Mariana López Treviño',   'mariana.lopez@correo.mx',  '$2b$12$C6UzMDM.H6dfI/f/IKcEeO3Yp2YHl3pA9cS9k6Yq2u7m1dO6zq1Wy', '8341001001'),
 ('Jorge Ramírez Castillo',  'jorge.ramirez@correo.mx',  '$2b$12$C6UzMDM.H6dfI/f/IKcEeO3Yp2YHl3pA9cS9k6Yq2u7m1dO6zq1Wy', '8341001002'),
 ('Fernanda Garza Salinas',  'fernanda.garza@correo.mx', '$2b$12$C6UzMDM.H6dfI/f/IKcEeO3Yp2YHl3pA9cS9k6Yq2u7m1dO6zq1Wy', '8341001003');

INSERT INTO inventario (sku, existencias, stock_minimo) VALUES
 ('REF-LG-GT32',    8, 2),   -- Refrigerador LG
 ('REF-MAB-RMS400', 4, 2),   -- Refrigerador Mabe
 ('LAV-WHR-8MWTW',  6, 2),   -- Lavadora Whirlpool
 ('TV-SAM-55CU',   10, 3),   -- Pantalla Samsung 55"
 ('LAP-LEN-IP3',    5, 2),   -- Laptop Lenovo
 ('CAM-OXF-AZM',   40, 10),  -- Camisa Oxford azul M
 ('CAM-OXF-BLL',   35, 10),  -- Camisa Oxford blanca L
 ('PAN-MEZ-32',    30, 8),   -- Pantalón de mezclilla 32
 ('TEN-NIK-REV7',  12, 4),   -- Tenis Nike Revolution 7
 ('SAR-TFL-24',     1, 3);   -- Sartén T-fal: ÚLTIMA PIEZA (prueba de concurrencia)

INSERT INTO movimientos_inventario (sku, tipo, cantidad)
SELECT sku, 'ENTRADA', existencias FROM inventario;

-- Compras históricas para el historial y las recomendaciones
SELECT confirmar_compra(1, '[{"sku":"TV-SAM-55CU","nombre":"Pantalla Samsung 55\" Crystal UHD","cantidad":1,"precio":9499.00},
                             {"sku":"LAP-LEN-IP3","nombre":"Laptop Lenovo IdeaPad 3","cantidad":1,"precio":11999.00}]',
                        'a1f0c3e2-0000-4000-8000-000000000001');
SELECT confirmar_compra(2, '[{"sku":"CAM-OXF-AZM","nombre":"Camisa Oxford azul M","cantidad":2,"precio":549.00},
                             {"sku":"PAN-MEZ-32","nombre":"Pantalón de mezclilla 32","cantidad":1,"precio":799.00}]',
                        'a1f0c3e2-0000-4000-8000-000000000002');
SELECT confirmar_compra(3, '[{"sku":"TV-SAM-55CU","nombre":"Pantalla Samsung 55\" Crystal UHD","cantidad":1,"precio":9499.00},
                             {"sku":"LAP-LEN-IP3","nombre":"Laptop Lenovo IdeaPad 3","cantidad":1,"precio":11999.00},
                             {"sku":"TEN-NIK-REV7","nombre":"Tenis Nike Revolution 7","cantidad":1,"precio":1299.00}]',
                        'a1f0c3e2-0000-4000-8000-000000000003');
SELECT confirmar_compra(1, '[{"sku":"CAM-OXF-BLL","nombre":"Camisa Oxford blanca L","cantidad":1,"precio":549.00}]',
                        'a1f0c3e2-0000-4000-8000-000000000004');
