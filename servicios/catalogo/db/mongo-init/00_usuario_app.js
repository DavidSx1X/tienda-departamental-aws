// Usuario de la aplicación con permisos sólo sobre la base "catalogo".
// mongosh permite leer variables de entorno del contenedor con process.env.
db.getSiblingDB("catalogo").createUser({
  user: process.env.MONGO_APP_USER,
  pwd:  process.env.MONGO_APP_PASSWORD,
  roles: [{ role: "readWrite", db: "catalogo" }]
});
