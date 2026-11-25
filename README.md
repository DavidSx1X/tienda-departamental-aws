# Tienda Departamental en AWS — Proyecto Final

Bases de Datos en la Nube · Universidad Politécnica de Victoria · Docente: Luis Roberto Flores de la Fuente

Tres servicios independientes, cada uno dueño de su base de datos:

| Servicio | Base de datos | EC2 (subred privada) | Puerto API |
|---|---|---|---|
| Catálogo y reseñas | MongoDB 7 + Redis (caché cache-aside) | 10.0.2.10 | 3001 |
| Carrito y sesiones | Redis 7 (AOF) | 10.0.2.20 | 3002 |
| Órdenes e inventario | PostgreSQL 16 | 10.0.2.30 | 3003 |

Toda petición externa entra por el **gateway Nginx** (10.0.1.10, puerto 80), que también es bastión SSH e instancia NAT.
Diagrama: `docs/diagrama_arquitectura.png`.

## Estructura

```
infra/
  aws/01_crear_infra.sh        VPC, subredes, Security Groups y 4 EC2 (AWS CLI)
  aws/99_borrar_infra.sh       Elimina todo al terminar el proyecto
  aws/user-data/               Arranque de gateway (Nginx + NAT) y de servicios (Docker)
  nginx/gateway.conf           Ruteo /api/catalogo, /api/carrito, /api/ordenes
servicios/
  catalogo/  docker-compose.yml · db/mongo-init/ ($jsonSchema, índices, datos) · redis/redis-cache.conf
  carrito/   docker-compose.yml · redis/redis-carrito.conf · redis/estructura_claves.redis
  ordenes/   docker-compose.yml · db/init/ (esquema, función confirmar_compra, semilla, rol de la app)
pruebas/
  verificar_bd.sh               Evidencia de cada base de datos (correr dentro de cada EC2)
  verificar_puertos_externos.sh Demuestra que sólo el 80 está expuesto (correr desde la laptop)
  prueba_concurrencia_bd.sh     Dos compras simultáneas de la última pieza
```

## Despliegue rápido

```bash
# 1) Desde CloudShell o una terminal con AWS CLI configurado
export AWS_REGION=us-east-1 KEY_NAME=tienda-equipo MI_IP=$(curl -s https://checkip.amazonaws.com)/32
./infra/aws/01_crear_infra.sh

# 2) Configurar SSH (alias gw, catalogo, carrito, ordenes) y desplegar las bases de datos
cp infra/ssh_config_ejemplo ~/.ssh/config   # reemplazar <IP_GATEWAY>
./infra/desplegar_servicios.sh               # genera .env con contraseñas aleatorias y hace docker compose up -d

# 3) Evidencia
ssh ordenes '~/tienda-departamental/pruebas/verificar_bd.sh ordenes'
./pruebas/verificar_puertos_externos.sh <IP_GATEWAY>
```

> `desplegar_servicios.sh` copia el proyecto por SSH, así que no hace falta que el repositorio sea público.
> Para entrar por SSH desde otra computadora, agregar su IP al Security Group del gateway:
> `aws ec2 authorize-security-group-ingress --group-id <SG_GW> --protocol tcp --port 22 --cidr <TU_IP>/32`

## Reglas del equipo

- Una rama por módulo (`feat/infra`, `feat/ordenes`, `feat/catalogo`, `feat/carrito`) y pull request a `main`.
- **Nunca** subir `.env`, llaves `.pem` ni los archivos `infra/aws/salida_*.env` (ya están en `.gitignore`).
- Al terminar las presentaciones: `./infra/aws/99_borrar_infra.sh infra/aws/salida_<fecha>.env`.

| Integrante | Rol | Carpeta |
|---|---|---|
| David Salvador Contreras Grimaldo | 1 + 5: infraestructura, seguridad, integración, API y pruebas | `infra/`, `pruebas/` |
| Ulises Gael Zamarripa Villanueva | 2: capa relacional | `servicios/ordenes/` |
| Angel Thomas Nuñez Hernandez | 3 + 4: capa de documentos y capa de caché | `servicios/catalogo/`, `servicios/carrito/` |
