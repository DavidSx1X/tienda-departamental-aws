#!/bin/bash
# User data de los EC2 privados (catalogo, carrito, ordenes) — Amazon Linux 2023.
# Instala Docker + Docker Compose y clona el repositorio. Requiere que el gateway (NAT) ya esté arriba.
set -eux
until curl -s --max-time 5 https://download.docker.com >/dev/null; do sleep 10; done
dnf update -y
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
# 2 GB de swap: la t3.micro sólo tiene 1 GB de RAM y MongoDB lo necesita
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
# El proyecto se copia después con infra/desplegar_servicios.sh (no requiere repo público)
