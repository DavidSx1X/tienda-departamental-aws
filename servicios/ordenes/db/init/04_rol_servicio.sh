#!/bin/sh
# Usuario de la aplicación con privilegios mínimos (sin DDL).
# Lee la contraseña de las variables de entorno del contenedor.
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
CREATE ROLE ${APP_DB_USER} LOGIN PASSWORD '${APP_DB_PASSWORD}';
GRANT USAGE ON SCHEMA tienda TO ${APP_DB_USER};
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA tienda TO ${APP_DB_USER};
GRANT USAGE ON ALL SEQUENCES IN SCHEMA tienda TO ${APP_DB_USER};
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tienda TO ${APP_DB_USER};
ALTER ROLE ${APP_DB_USER} SET search_path = tienda, public;
SQL
