#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${BLUE}${BOLD}============================================================${NC}"
echo -e "${BLUE}${BOLD}   INFRAESTRUTURA CORPORATIVA — Setup Automático           ${NC}"
echo -e "${BLUE}${BOLD}   github.com/RainerJustiniano/projeto-iac                 ${NC}"
echo -e "${BLUE}${BOLD}============================================================${NC}"

echo -e "\n${YELLOW}[1/4] Instalando dependências...${NC}"
sudo apt-get update -qq
sudo apt-get install -y podman ansible sshpass git -qq
echo -e "  ${GREEN}✓${NC} Dependências instaladas"

echo -e "\n${YELLOW}[2/4] Criando infraestrutura...${NC}"
podman rm -f dns adminsrv worksrv datastore client 2>/dev/null
podman network rm -f admin_net work_net data_net 2>/dev/null
podman network rm -f projeto-iac_admin_net projeto-iac_work_net projeto-iac_data_net 2>/dev/null

echo "  Construindo imagem base..."
podman build -t projeto-iac/base ./containers/base -q

echo "  Criando redes..."
podman network create --subnet 192.168.10.0/24 --gateway 192.168.10.1 admin_net
podman network create --subnet 192.168.20.0/24 --gateway 192.168.20.1 work_net
podman network create --subnet 192.168.30.0/24 --gateway 192.168.30.1 data_net

echo "  Iniciando containers..."

# DNS — usa volume mount (contorna bug do ENTRYPOINT)
podman run -d --name dns --hostname dns.lab \
  --network admin_net --ip 192.168.10.2 \
  -v "$HOME/projeto-iac/containers/dns/Corefile:/etc/coredns/Corefile:ro" \
  -v "$HOME/projeto-iac/containers/dns/hosts:/etc/coredns/hosts:ro" \
  coredns/coredns:1.11.1 -conf /etc/coredns/Corefile
podman network connect --ip 192.168.20.2 work_net dns

podman run -d --name adminsrv --hostname adminsrv.lab \
  --network admin_net --ip 192.168.10.10 \
  --dns 192.168.10.2 -p 2210:22 --cap-add NET_RAW projeto-iac/base
podman network connect data_net adminsrv

podman run -d --name worksrv --hostname worksrv.lab \
  --network work_net --ip 192.168.20.10 \
  --dns 192.168.20.2 -p 2220:22 --cap-add NET_RAW projeto-iac/base
podman network connect data_net worksrv

podman run -d --name datastore --hostname datastore.lab \
  --network data_net --ip 192.168.30.30 \
  -p 2230:22 --cap-add NET_RAW projeto-iac/base

podman run -d --name client --hostname client.lab \
  --network admin_net --ip 192.168.10.100 \
  --dns 192.168.10.2 -p 2240:22 --cap-add NET_RAW projeto-iac/base
podman network connect work_net client

echo "  Aguardando containers..."
sleep 8

echo -e "\n${YELLOW}[3/4] Executando Ansible...${NC}"
cd "$HOME/projeto-iac/ansible"
ansible-playbook -i inventory playbook.yml 2>&1 | grep -E "PLAY RECAP|ok=|failed=|changed="

echo -e "\n${YELLOW}[4/4] Rodando testes...${NC}"
cd "$HOME/projeto-iac/scripts"
chmod +x test.sh
./test.sh

echo -e "\n${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}   Pronto! Credenciais de acesso:                         ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "  ssh -p 2210 alice@localhost  →  senha: Alice@2024!"
echo -e "  ssh -p 2220 bob@localhost    →  senha: Bob@2024!"
echo -e "  ssh -p 2220 carol@localhost  →  senha: Carol@2024!"
echo ""
