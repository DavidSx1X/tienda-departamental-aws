#!/usr/bin/env bash
# Borra TODO lo creado por 01_crear_infra.sh. Ejecutar al terminar el proyecto (evita cargos).
# Uso: ./99_borrar_infra.sh salida_AAAAMMDD_HHMM.env
set -uo pipefail
cd "$(dirname "$0")"
source "${1:?Indica el archivo salida_*.env}"
aws ec2 terminate-instances --instance-ids "$EC2_GW" "$EC2_CAT" "$EC2_CAR" "$EC2_ORD" >/dev/null
aws ec2 wait instance-terminated --instance-ids "$EC2_GW" "$EC2_CAT" "$EC2_CAR" "$EC2_ORD"
for g in "$SG_CAT" "$SG_CAR" "$SG_ORD" "$SG_GW"; do
  aws ec2 describe-security-groups --group-ids "$g" --query 'SecurityGroups[0].IpPermissions' --output json > /tmp/perm.json
  [ "$(cat /tmp/perm.json)" != "[]" ] && aws ec2 revoke-security-group-ingress --group-id "$g" --ip-permissions file:///tmp/perm.json >/dev/null
done
for g in "$SG_CAT" "$SG_CAR" "$SG_ORD" "$SG_GW"; do aws ec2 delete-security-group --group-id "$g"; done
for s in "$SUB_PUB" "$SUB_PRIV"; do aws ec2 delete-subnet --subnet-id "$s"; done
for r in "$RT_PUB" "$RT_PRIV"; do aws ec2 delete-route-table --route-table-id "$r"; done
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW"
aws ec2 delete-vpc --vpc-id "$VPC"
echo "Infraestructura eliminada. Verifica en la consola que no queden volúmenes EBS ni IPs elásticas."
