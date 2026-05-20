#!/bin/bash
# =============================================================
# Script de inicialização da infraestrutura com Podman
# Substitui o podman-compose contornando limitação de multi-rede
# =============================================================

echo ">>> Construindo imagens..."
podman build -t projeto-iac/base ./containers/base
podman build -t projeto-iac/dns  ./containers/dns

echo ">>> Criando redes..."
podman network create --subnet 192.168.10.0/24 --gateway 192.168.10.1 admin_net 2>/dev/null || true
podman network create --subnet 192.168.20.0/24 --gateway 192.168.20.1 work_net  2>/dev/null || true
podman network create --subnet 192.168.30.0/24 --gateway 192.168.30.1 data_net  2>/dev/null || true

echo ">>> Iniciando containers..."

# DNS
podman run -d --name dns --hostname dns.lab \
  --network admin_net --ip 192.168.10.2 \
  projeto-iac/dns
podman network connect --ip 192.168.20.2 work_net dns

# ADMINSRV
podman run -d --name adminsrv --hostname adminsrv.lab \
  --network admin_net --ip 192.168.10.10 \
  --dns 192.168.10.2 -p 2210:22 \
  projeto-iac/base
podman network connect data_net adminsrv

# WORKSRV
podman run -d --name worksrv --hostname worksrv.lab \
  --network work_net --ip 192.168.20.10 \
  --dns 192.168.20.2 -p 2220:22 \
  projeto-iac/base
podman network connect data_net worksrv

# DATASTORE
podman run -d --name datastore --hostname datastore.lab \
  --network data_net --ip 192.168.30.30 \
  -p 2230:22 \
  projeto-iac/base

# CLIENT
podman run -d --name client --hostname client.lab \
  --network admin_net --ip 192.168.10.100 \
  --dns 192.168.10.2 -p 2240:22 \
  projeto-iac/base
podman network connect work_net client

echo ""
echo ">>> Status dos containers:"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
