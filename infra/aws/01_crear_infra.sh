#!/usr/bin/env bash
# =============================================================================
#  Crea la infraestructura del proyecto en AWS con AWS CLI v2.
#  Responsable: Rol 1 (infraestructura, seguridad y despliegue)
#
#  Requisitos: aws configure (o AWS CloudShell), un key pair existente.
#  Uso:
#     export AWS_REGION=us-east-1
#     export KEY_NAME=tienda-equipo          # nombre del key pair en EC2
#     export MI_IP=$(curl -s https://checkip.amazonaws.com)/32
#     # IPs del resto del equipo, separadas por espacio (opcional):
#     export IPS_EQUIPO="189.x.x.x/32 201.x.x.x/32"
#     ./01_crear_infra.sh
#
#  Resultado: VPC 10.0.0.0/16, subred pública 10.0.1.0/24 (gateway + bastión + NAT),
#  subred privada 10.0.2.0/24 (catalogo, carrito, ordenes), 4 Security Groups y 4 EC2 t3.micro.
#  Los IDs creados se guardan en salida_<fecha>.env para poder borrarlos con 99_borrar_infra.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
: "${AWS_REGION:?Define AWS_REGION}" "${KEY_NAME:?Define KEY_NAME}" "${MI_IP:?Define MI_IP}"
TIPO=${TIPO_INSTANCIA:-t3.micro}
P=tienda
OUT="salida_$(date +%Y%m%d_%H%M).env"
tag () { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Proyecto,Value=$P}]"; }
guarda () { echo "$1=$2" | tee -a "$OUT"; }

AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
      --query Parameter.Value --output text)
guarda AMI "$AMI"

# ---------------- Red ----------------
VPC=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications "$(tag vpc $P-vpc)" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames
guarda VPC "$VPC"
AZ=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
SUB_PUB=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 10.0.1.0/24 --availability-zone "$AZ" \
          --tag-specifications "$(tag subnet $P-publica)" --query Subnet.SubnetId --output text)
SUB_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC" --cidr-block 10.0.2.0/24 --availability-zone "$AZ" \
          --tag-specifications "$(tag subnet $P-privada)" --query Subnet.SubnetId --output text)
guarda SUB_PUB "$SUB_PUB"; guarda SUB_PRIV "$SUB_PRIV"

IGW=$(aws ec2 create-internet-gateway --tag-specifications "$(tag internet-gateway $P-igw)" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC" --internet-gateway-id "$IGW"
guarda IGW "$IGW"
RT_PUB=$(aws ec2 create-route-table --vpc-id "$VPC" --tag-specifications "$(tag route-table $P-rt-publica)" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RT_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null
aws ec2 associate-route-table --route-table-id "$RT_PUB" --subnet-id "$SUB_PUB" >/dev/null
RT_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC" --tag-specifications "$(tag route-table $P-rt-privada)" --query RouteTable.RouteTableId --output text)
aws ec2 associate-route-table --route-table-id "$RT_PRIV" --subnet-id "$SUB_PRIV" >/dev/null
guarda RT_PUB "$RT_PUB"; guarda RT_PRIV "$RT_PRIV"

# ---------------- Security Groups ----------------
sg () { aws ec2 create-security-group --vpc-id "$VPC" --group-name "$1" --description "$2" \
          --tag-specifications "$(tag security-group $1)" --query GroupId --output text; }
SG_GW=$(sg $P-sg-gateway  "API publica 80 y SSH solo desde IPs del equipo")
SG_CAT=$(sg $P-sg-catalogo "Catalogo: 3001 desde gateway y carrito")
SG_CAR=$(sg $P-sg-carrito  "Carrito: 3002 desde gateway")
SG_ORD=$(sg $P-sg-ordenes  "Ordenes: 3003 desde gateway, carrito y catalogo")
guarda SG_GW "$SG_GW"; guarda SG_CAT "$SG_CAT"; guarda SG_CAR "$SG_CAR"; guarda SG_ORD "$SG_ORD"

desde_sg () { aws ec2 authorize-security-group-ingress --group-id "$1" --protocol tcp --port "$2" --source-group "$3" >/dev/null; }
desde_ip () { aws ec2 authorize-security-group-ingress --group-id "$1" --protocol tcp --port "$2" --cidr "$3" >/dev/null; }

# Gateway: único puerto público = 80. SSH sólo desde las IPs del equipo.
desde_ip "$SG_GW" 80 0.0.0.0/0
for ip in $MI_IP ${IPS_EQUIPO:-}; do desde_ip "$SG_GW" 22 "$ip"; done
# Tráfico de salida de la subred privada que pasa por el gateway (NAT)
aws ec2 authorize-security-group-ingress --group-id "$SG_GW" --protocol all --cidr 10.0.2.0/24 >/dev/null

# Servicios: sólo su puerto de API, y sólo desde quien lo necesita. SSH sólo desde el bastión.
desde_sg "$SG_CAT" 3001 "$SG_GW";  desde_sg "$SG_CAT" 3001 "$SG_CAR"
desde_sg "$SG_CAR" 3002 "$SG_GW"
desde_sg "$SG_ORD" 3003 "$SG_GW";  desde_sg "$SG_ORD" 3003 "$SG_CAR"; desde_sg "$SG_ORD" 3003 "$SG_CAT"
for g in "$SG_CAT" "$SG_CAR" "$SG_ORD"; do desde_sg "$g" 22 "$SG_GW"; done
# NOTA: los puertos 5432, 27017 y 6379 NO se abren en ningún SG. Además, en docker-compose
# las bases de datos sólo escuchan en 127.0.0.1 dentro de su propia instancia.

# ---------------- EC2 ----------------
UD_GW=$(mktemp)
python3 - "$UD_GW" <<'PY'
import sys
s=open('user-data/gateway.sh').read().replace('__GATEWAY_CONF__', open('../nginx/gateway.conf').read().rstrip())
open(sys.argv[1],'w').write(s)
PY

ec2 () {  # nombre subred sg ip-privada user-data [ip-publica]
  aws ec2 run-instances --image-id "$AMI" --instance-type "$TIPO" --key-name "$KEY_NAME" \
    --network-interfaces "DeviceIndex=0,SubnetId=$2,Groups=$3,PrivateIpAddress=$4,AssociatePublicIpAddress=${6:-false}" \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=10,VolumeType=gp3,DeleteOnTermination=true}' \
    --metadata-options HttpTokens=required \
    --user-data "file://$5" --tag-specifications "$(tag instance $P-$1)" \
    --query 'Instances[0].InstanceId' --output text; }

EC2_GW=$(ec2 gateway "$SUB_PUB" "$SG_GW" 10.0.1.10 "$UD_GW" true)
guarda EC2_GW "$EC2_GW"
aws ec2 wait instance-running --instance-ids "$EC2_GW"
# El gateway actúa como instancia NAT: debe poder reenviar paquetes que no son suyos
aws ec2 modify-instance-attribute --instance-id "$EC2_GW" --no-source-dest-check
ENI_GW=$(aws ec2 describe-instances --instance-ids "$EC2_GW" --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' --output text)
aws ec2 create-route --route-table-id "$RT_PRIV" --destination-cidr-block 0.0.0.0/0 --network-interface-id "$ENI_GW" >/dev/null

EC2_CAT=$(ec2 catalogo "$SUB_PRIV" "$SG_CAT" 10.0.2.10 user-data/servicio.sh); guarda EC2_CAT "$EC2_CAT"
EC2_CAR=$(ec2 carrito  "$SUB_PRIV" "$SG_CAR" 10.0.2.20 user-data/servicio.sh); guarda EC2_CAR "$EC2_CAR"
EC2_ORD=$(ec2 ordenes  "$SUB_PRIV" "$SG_ORD" 10.0.2.30 user-data/servicio.sh); guarda EC2_ORD "$EC2_ORD"
aws ec2 wait instance-running --instance-ids "$EC2_CAT" "$EC2_CAR" "$EC2_ORD"

IP_GW=$(aws ec2 describe-instances --instance-ids "$EC2_GW" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
guarda IP_GW "$IP_GW"
rm -f "$UD_GW"
cat <<FIN

Listo. API pública:      http://$IP_GW/health
Entrar al bastión:       ssh -i $KEY_NAME.pem ec2-user@$IP_GW
Entrar a un servicio:    ssh -i $KEY_NAME.pem -J ec2-user@$IP_GW ec2-user@10.0.2.10   (catalogo)
                                                                   10.0.2.20   (carrito)
                                                                   10.0.2.30   (ordenes)
Túnel a PostgreSQL:      ssh -i $KEY_NAME.pem -J ec2-user@$IP_GW -L 5432:localhost:5432 ec2-user@10.0.2.30
Túnel a MongoDB:         ssh -i $KEY_NAME.pem -J ec2-user@$IP_GW -L 27017:localhost:27017 ec2-user@10.0.2.10
IDs guardados en:        infra/aws/$OUT  (NO subir al repositorio)
FIN
