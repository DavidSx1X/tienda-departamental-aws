// =============================================================================
//  Servicio de catálogo — Inicialización de MongoDB 7
//  Proyecto Final: Tienda Departamental · Bases de Datos en la Nube · UPV
//  Responsable de la capa: Rol 3 (capa de documentos)
//
//  Se ejecuta automáticamente al crear el contenedor (carpeta
//  /docker-entrypoint-initdb.d). También: mongosh "mongodb://..." --file 01_colecciones.js
//
//  Crea 3 colecciones con validación $jsonSchema, sus índices y datos de prueba.
//  Los SKU coinciden con la tabla inventario del servicio de órdenes.
// =============================================================================

db = db.getSiblingDB("catalogo");

// -----------------------------------------------------------------------------
// 1) categorias — árbol de categorías con patrón "ancestros" (array de slugs)
//    Permite filtrar "todo lo de Línea blanca" con un solo índice.
// -----------------------------------------------------------------------------
db.createCollection("categorias", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "nombre", "ancestros"],
    additionalProperties: false,
    properties: {
      _id:       { bsonType: "string", pattern: "^[a-z0-9-]+$", description: "slug de la categoría" },
      nombre:    { bsonType: "string", minLength: 2, maxLength: 60 },
      padre:     { bsonType: ["string", "null"] },
      ancestros: { bsonType: "array", items: { bsonType: "string" } }
    }
  }},
  validationLevel: "strict",
  validationAction: "error"
});

// -----------------------------------------------------------------------------
// 2) productos — atributos variables según el tipo de producto.
//    Los campos comunes son obligatorios; "atributos" cambia por tipo y se
//    valida con anyOf: un refrigerador exige capacidad y eficiencia, una prenda
//    exige talla y color, un electrónico exige garantía. Otros tipos sólo
//    exigen que "atributos" sea un objeto.
// -----------------------------------------------------------------------------
const TIPOS_CON_REGLA = ["linea_blanca", "ropa", "calzado", "electronica"];

db.createCollection("productos", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["sku", "nombre", "tipo", "categoria", "precio", "atributos", "activo", "creado_en", "actualizado_en"],
    properties: {
      sku:         { bsonType: "string", pattern: "^[A-Z0-9-]{3,30}$" },
      nombre:      { bsonType: "string", minLength: 3, maxLength: 160 },
      descripcion: { bsonType: "string", maxLength: 2000 },
      marca:       { bsonType: "string" },
      tipo:        { bsonType: "string" },
      categoria: {
        bsonType: "object",
        required: ["slug", "nombre", "ruta"],
        properties: {
          slug:   { bsonType: "string" },
          nombre: { bsonType: "string" },
          ruta:   { bsonType: "array", items: { bsonType: "string" } }
        }
      },
      precio:      { bsonType: "decimal", minimum: NumberDecimal("0") },
      precio_anterior: { bsonType: ["decimal", "null"] },
      moneda:      { enum: ["MXN"] },
      etiquetas:   { bsonType: "array", items: { bsonType: "string" }, uniqueItems: true },
      imagenes:    { bsonType: "array", maxItems: 10, items: { bsonType: "string" } },
      atributos:   { bsonType: "object" },
      calificacion: {
        bsonType: "object",
        required: ["promedio", "total"],
        properties: {
          promedio: { bsonType: ["double", "int"], minimum: 0, maximum: 5 },
          total:    { bsonType: "int", minimum: 0 }
        }
      },
      resenas_recientes: { bsonType: "array", maxItems: 3 },   // patrón subset
      activo:         { bsonType: "bool" },
      creado_en:      { bsonType: "date" },
      actualizado_en: { bsonType: "date" }
    },
    anyOf: [
      { properties: { tipo: { enum: ["linea_blanca"] },
                      atributos: { bsonType: "object", required: ["capacidad", "eficiencia_energetica", "voltaje"] } } },
      { properties: { tipo: { enum: ["ropa"] },
                      atributos: { bsonType: "object", required: ["talla", "color", "material", "genero"] } } },
      { properties: { tipo: { enum: ["calzado"] },
                      atributos: { bsonType: "object", required: ["talla_mx", "color", "genero"] } } },
      { properties: { tipo: { enum: ["electronica"] },
                      atributos: { bsonType: "object", required: ["garantia_meses"] } } },
      { properties: { tipo: { not: { enum: TIPOS_CON_REGLA } } } }
    ]
  }},
  validationLevel: "strict",
  validationAction: "error"
});

// -----------------------------------------------------------------------------
// 3) resenas — colección aparte (referencia por sku): crecen sin límite y se
//    consultan paginadas. El producto sólo guarda el resumen (promedio, total)
//    y las 3 más recientes para mostrar el detalle en UNA lectura.
// -----------------------------------------------------------------------------
db.createCollection("resenas", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["producto_sku", "cliente_id", "autor", "calificacion", "comentario", "fecha"],
    additionalProperties: false,
    properties: {
      _id:          { bsonType: "objectId" },
      producto_sku: { bsonType: "string", pattern: "^[A-Z0-9-]{3,30}$" },
      cliente_id:   { bsonType: ["int", "long"], minimum: 1 },
      autor:        { bsonType: "string", maxLength: 80 },
      calificacion: { bsonType: "int", minimum: 1, maximum: 5 },
      titulo:       { bsonType: "string", maxLength: 100 },
      comentario:   { bsonType: "string", minLength: 5, maxLength: 1500 },
      compra_verificada: { bsonType: "bool" },
      util:         { bsonType: "int", minimum: 0 },
      fecha:        { bsonType: "date" }
    }
  }},
  validationLevel: "strict",
  validationAction: "error"
});

// -----------------------------------------------------------------------------
// Índices (cada uno respalda una consulta concreta de la API)
// -----------------------------------------------------------------------------
db.productos.createIndex({ sku: 1 }, { unique: true, name: "ux_sku" });                         // GET /productos/{sku}
db.productos.createIndex({ "categoria.ruta": 1, precio: 1 }, { name: "ix_categoria_precio",     // filtro categoría + rango de precio
                           partialFilterExpression: { activo: true } });
db.productos.createIndex({ precio: 1 }, { name: "ix_precio", partialFilterExpression: { activo: true } }); // filtro sólo por precio
db.productos.createIndex({ nombre: "text", marca: "text", descripcion: "text" },
                         { name: "tx_busqueda", default_language: "spanish", weights: { nombre: 10, marca: 5, descripcion: 1 } });
db.resenas.createIndex({ producto_sku: 1, fecha: -1 }, { name: "ix_producto_fecha" });           // reseñas paginadas por producto
db.resenas.createIndex({ producto_sku: 1, cliente_id: 1 }, { unique: true, name: "ux_una_resena_por_cliente" });
db.categorias.createIndex({ ancestros: 1 }, { name: "ix_ancestros" });

// -----------------------------------------------------------------------------
// Datos de prueba
// -----------------------------------------------------------------------------
const ahora = new Date("2026-11-18T10:00:00-06:00");
const D = (x) => NumberDecimal(String(x));

db.categorias.insertMany([
  { _id: "linea-blanca",   nombre: "Línea blanca",   padre: null,           ancestros: [] },
  { _id: "refrigeradores", nombre: "Refrigeradores", padre: "linea-blanca", ancestros: ["linea-blanca"] },
  { _id: "lavadoras",      nombre: "Lavadoras",      padre: "linea-blanca", ancestros: ["linea-blanca"] },
  { _id: "electronica",    nombre: "Electrónica",    padre: null,           ancestros: [] },
  { _id: "pantallas",      nombre: "Pantallas",      padre: "electronica",  ancestros: ["electronica"] },
  { _id: "computo",        nombre: "Cómputo",        padre: "electronica",  ancestros: ["electronica"] },
  { _id: "ropa",           nombre: "Ropa",           padre: null,           ancestros: [] },
  { _id: "camisas",        nombre: "Camisas",        padre: "ropa",         ancestros: ["ropa"] },
  { _id: "pantalones",     nombre: "Pantalones",     padre: "ropa",         ancestros: ["ropa"] },
  { _id: "calzado",        nombre: "Calzado",        padre: null,           ancestros: [] },
  { _id: "hogar",          nombre: "Hogar",          padre: null,           ancestros: [] },
  { _id: "cocina",         nombre: "Cocina",         padre: "hogar",        ancestros: ["hogar"] }
]);

const cat = (slug, nombre, ruta) => ({ slug, nombre, ruta });

db.productos.insertMany([
  { sku: "REF-LG-GT32", nombre: "Refrigerador LG 11 pies³ Inverter", marca: "LG", tipo: "linea_blanca",
    descripcion: "Refrigerador top mount con compresor Smart Inverter y despachador de agua.",
    categoria: cat("refrigeradores", "Refrigeradores", ["linea-blanca", "refrigeradores"]),
    precio: D("15999.00"), precio_anterior: D("17499.00"), moneda: "MXN", etiquetas: ["inverter", "ahorro-energia"],
    imagenes: ["https://cdn.tienda.mx/p/REF-LG-GT32/1.jpg"],
    atributos: { capacidad: { valor: 11, unidad: "pies3" }, eficiencia_energetica: "A+", voltaje: "127 V",
                 color: "Plata", dimensiones_cm: { alto: 172, ancho: 60, fondo: 68 }, despachador_agua: true, puertas: 2 },
    calificacion: { promedio: 4.5, total: NumberInt(2) },
    resenas_recientes: [ { autor: "Mariana L.", calificacion: NumberInt(5), titulo: "Muy silencioso", fecha: new Date("2026-11-10T12:00:00-06:00") },
                         { autor: "Jorge R.",   calificacion: NumberInt(4), titulo: "Buen espacio",   fecha: new Date("2026-11-02T09:30:00-06:00") } ],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "REF-MAB-RMS400", nombre: "Refrigerador Mabe 14 pies³", marca: "Mabe", tipo: "linea_blanca",
    categoria: cat("refrigeradores", "Refrigeradores", ["linea-blanca", "refrigeradores"]),
    precio: D("12999.00"), moneda: "MXN", etiquetas: [],
    atributos: { capacidad: { valor: 14, unidad: "pies3" }, eficiencia_energetica: "A", voltaje: "127 V", color: "Grafito", puertas: 2 },
    calificacion: { promedio: 0, total: NumberInt(0) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "LAV-WHR-8MWTW", nombre: "Lavadora Whirlpool 20 kg carga superior", marca: "Whirlpool", tipo: "linea_blanca",
    categoria: cat("lavadoras", "Lavadoras", ["linea-blanca", "lavadoras"]),
    precio: D("10499.00"), moneda: "MXN", etiquetas: ["xpert-system"],
    atributos: { capacidad: { valor: 20, unidad: "kg" }, eficiencia_energetica: "A", voltaje: "127 V", ciclos: 12, tipo_carga: "superior" },
    calificacion: { promedio: 0, total: NumberInt(0) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "TV-SAM-55CU", nombre: "Pantalla Samsung 55\" Crystal UHD 4K", marca: "Samsung", tipo: "electronica",
    categoria: cat("pantallas", "Pantallas", ["electronica", "pantallas"]),
    precio: D("9499.00"), moneda: "MXN", etiquetas: ["4k", "smart-tv"],
    atributos: { garantia_meses: 12, pulgadas: 55, resolucion: "3840x2160", sistema_operativo: "Tizen", puertos_hdmi: 3 },
    calificacion: { promedio: 5, total: NumberInt(1) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "LAP-LEN-IP3", nombre: "Laptop Lenovo IdeaPad 3 15\"", marca: "Lenovo", tipo: "electronica",
    categoria: cat("computo", "Cómputo", ["electronica", "computo"]),
    precio: D("11999.00"), moneda: "MXN", etiquetas: ["estudiantes"],
    atributos: { garantia_meses: 12, procesador: "Ryzen 5 7520U", ram_gb: 8, almacenamiento: { tipo: "SSD", gb: 512 }, pantalla_pulgadas: 15.6 },
    calificacion: { promedio: 0, total: NumberInt(0) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "CAM-OXF-AZM", nombre: "Camisa Oxford azul manga larga", marca: "Dockers", tipo: "ropa",
    categoria: cat("camisas", "Camisas", ["ropa", "camisas"]),
    precio: D("549.00"), moneda: "MXN", etiquetas: ["formal"],
    atributos: { talla: "M", color: "Azul cielo", material: "100% algodón", genero: "hombre", corte: "regular", manga: "larga" },
    calificacion: { promedio: 0, total: NumberInt(0) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "CAM-OXF-BLL", nombre: "Camisa Oxford blanca manga larga", marca: "Dockers", tipo: "ropa",
    categoria: cat("camisas", "Camisas", ["ropa", "camisas"]),
    precio: D("549.00"), moneda: "MXN", etiquetas: ["formal"],
    atributos: { talla: "L", color: "Blanco", material: "100% algodón", genero: "hombre", corte: "regular", manga: "larga" },
    calificacion: { promedio: 0, total: NumberInt(0) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "PAN-MEZ-32", nombre: "Pantalón de mezclilla corte recto", marca: "Levi's", tipo: "ropa",
    categoria: cat("pantalones", "Pantalones", ["ropa", "pantalones"]),
    precio: D("799.00"), moneda: "MXN", etiquetas: [],
    atributos: { talla: "32x32", color: "Azul índigo", material: "98% algodón, 2% elastano", genero: "hombre", corte: "recto" },
    calificacion: { promedio: 0, total: NumberInt(0) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "TEN-NIK-REV7", nombre: "Tenis Nike Revolution 7", marca: "Nike", tipo: "calzado",
    categoria: cat("calzado", "Calzado", ["calzado"]),
    precio: D("1299.00"), moneda: "MXN", etiquetas: ["running"],
    atributos: { talla_mx: 27, color: "Negro/Blanco", genero: "hombre", uso: "correr" },
    calificacion: { promedio: 0, total: NumberInt(0) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora },

  { sku: "SAR-TFL-24", nombre: "Sartén T-fal antiadherente 24 cm", marca: "T-fal", tipo: "cocina",
    categoria: cat("cocina", "Cocina", ["hogar", "cocina"]),
    precio: D("459.00"), moneda: "MXN", etiquetas: ["antiadherente"],
    atributos: { diametro_cm: 24, material: "Aluminio", apto_induccion: false },     // tipo sin regla: atributos libres
    calificacion: { promedio: 0, total: NumberInt(0) }, resenas_recientes: [],
    activo: true, creado_en: ahora, actualizado_en: ahora }
]);

db.resenas.insertMany([
  { producto_sku: "REF-LG-GT32", cliente_id: NumberInt(1), autor: "Mariana L.", calificacion: NumberInt(5), titulo: "Muy silencioso",
    comentario: "Casi no se escucha el compresor y enfría rápido.", compra_verificada: true, util: NumberInt(3), fecha: new Date("2026-11-10T12:00:00-06:00") },
  { producto_sku: "REF-LG-GT32", cliente_id: NumberInt(2), autor: "Jorge R.", calificacion: NumberInt(4), titulo: "Buen espacio",
    comentario: "Cabe bien en cocina chica; el despachador es práctico.", compra_verificada: false, util: NumberInt(0), fecha: new Date("2026-11-02T09:30:00-06:00") },
  { producto_sku: "TV-SAM-55CU", cliente_id: NumberInt(1), autor: "Mariana L.", calificacion: NumberInt(5), titulo: "Excelente imagen",
    comentario: "La imagen 4K se ve muy bien y las apps funcionan rápido.", compra_verificada: true, util: NumberInt(1), fecha: new Date("2026-11-12T20:15:00-06:00") }
]);

// -----------------------------------------------------------------------------
// Comprobación: un documento inválido debe ser RECHAZADO por el validador
// (refrigerador sin capacidad ni eficiencia energética)
// -----------------------------------------------------------------------------
try {
  db.productos.insertOne({ sku: "REF-INVALIDO", nombre: "Refrigerador sin datos", tipo: "linea_blanca",
    categoria: cat("refrigeradores", "Refrigeradores", ["linea-blanca", "refrigeradores"]),
    precio: D("100"), atributos: { color: "Blanco" }, activo: true, creado_en: ahora, actualizado_en: ahora });
  print("ERROR: el validador aceptó un documento inválido");
} catch (e) {
  print("OK: validador rechazó el refrigerador sin capacidad (" + e.code + " " + e.message + ")");
}

print("Colecciones: " + db.getCollectionNames().join(", "));
print("productos=" + db.productos.countDocuments() + " resenas=" + db.resenas.countDocuments() + " categorias=" + db.categorias.countDocuments());
