#!/bin/bash
# User data del EC2 "gateway" (Amazon Linux 2023): Nginx + NAT para la subred privada + bastión SSH.
set -eux
dnf update -y
dnf install -y nginx iptables-services git
# --- NAT: permite que las instancias privadas descarguen paquetes/imágenes sin NAT Gateway ($) ---
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-nat.conf
sysctl -p /etc/sysctl.d/90-nat.conf
IFACE=$(ip route | awk '/default/ {print $5; exit}')
iptables -t nat -A POSTROUTING -o "$IFACE" -s 10.0.2.0/24 -j MASQUERADE
iptables -F FORWARD
iptables -P FORWARD ACCEPT
iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables
# --- Nginx como API gateway ---
# El script 01_crear_infra.sh inserta aquí el contenido de infra/nginx/gateway.conf
cat > /etc/nginx/conf.d/gateway.conf <<'NGINX'
__GATEWAY_CONF__
NGINX
rm -f /etc/nginx/conf.d/default.conf
systemctl enable --now nginx
