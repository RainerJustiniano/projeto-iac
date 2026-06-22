#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_header() {
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}   INFRAESTRUTURA CORPORATIVA — Setup Automático           ${NC}"
  echo -e "${BLUE}${BOLD}   Projeto IaC com Podman + Ansible + DNS interno           ${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
}

print_step() {
  echo -e "\n${YELLOW}${BOLD}[$1] $2${NC}"
  echo -e "${YELLOW}------------------------------------------------------------${NC}"
}

print_ok() {
  echo -e "  ${GREEN}✓${NC} $1"
}

print_info() {
  echo -e "  ${BLUE}→${NC} $1"
}

print_error() {
  echo -e "  ${RED}✗${NC} $1"
}

check_project_root() {
  if [ ! -f "$PROJECT_DIR/setup.sh" ] || [ ! -d "$PROJECT_DIR/containers" ] || [ ! -d "$PROJECT_DIR/ansible" ] || [ ! -d "$PROJECT_DIR/scripts" ]; then
    print_error "Este script precisa ser executado na raiz do projeto."
    echo ""
    echo "Uso correto:"
    echo "  git clone https://github.com/RainerJustiniano/projeto-iac.git"
    echo "  cd projeto-iac"
    echo "  bash setup.sh"
    echo ""
    exit 1
  fi

  print_ok "Diretório do projeto encontrado: $PROJECT_DIR"
}

install_dependencies() {
  local missing=()

  command -v podman >/dev/null 2>&1 || missing+=("podman")
  command -v ansible >/dev/null 2>&1 || missing+=("ansible")
  command -v sshpass >/dev/null 2>&1 || missing+=("sshpass")
  command -v git >/dev/null 2>&1 || missing+=("git")

  if [ "${#missing[@]}" -eq 0 ]; then
    print_ok "Todas as dependências já estão instaladas"
    return
  fi

  print_info "Dependências ausentes: ${missing[*]}"

  if ! command -v apt-get >/dev/null 2>&1; then
    print_error "apt-get não encontrado. Instale manualmente: ${missing[*]}"
    exit 1
  fi

  print_info "Instalando dependências com apt-get..."
  sudo apt-get update -qq
  sudo apt-get install -y podman ansible sshpass git -qq

  print_ok "Dependências instaladas"
}

cleanup_environment() {
  print_info "Removendo containers antigos, se existirem..."

  podman rm -f dns adminsrv worksrv datastore client 2>/dev/null || true

  print_info "Removendo redes antigas, se existirem..."

  podman network rm -f admin_net work_net data_net 2>/dev/null || true
  podman network rm -f projeto-iac_admin_net projeto-iac_work_net projeto-iac_data_net 2>/dev/null || true

  print_ok "Ambiente antigo limpo"
}

build_images() {
  print_info "Criando imagem base dos servidores..."

  podman build -t projeto-iac/base:latest "$PROJECT_DIR/containers/base" -q

  print_ok "Imagem criada: projeto-iac/base:latest"

  print_info "Imagem do DNS utilizada: docker.io/coredns/coredns:1.11.1"
  print_ok "Imagens prontas"
}

create_networks() {
  print_info "Criando rede administrativa..."
  podman network create --subnet 192.168.10.0/24 --gateway 192.168.10.1 admin_net >/dev/null

  print_info "Criando rede operacional..."
  podman network create --subnet 192.168.20.0/24 --gateway 192.168.20.1 work_net >/dev/null

  print_info "Criando rede de dados..."
  podman network create --subnet 192.168.30.0/24 --gateway 192.168.30.1 data_net >/dev/null

  echo ""
  echo "  Redes criadas:"
  echo "  - admin_net : 192.168.10.0/24"
  echo "  - work_net  : 192.168.20.0/24"
  echo "  - data_net  : 192.168.30.0/24"

  print_ok "Redes criadas com sucesso"
}

create_containers() {
  print_info "Criando container DNS..."

  podman run -d --name dns --hostname dns.lab \
    --network admin_net --ip 192.168.10.2 \
    -v "$PROJECT_DIR/containers/dns/Corefile:/etc/coredns/Corefile:ro" \
    -v "$PROJECT_DIR/containers/dns/hosts:/etc/coredns/hosts:ro" \
    docker.io/coredns/coredns:1.11.1 -conf /etc/coredns/Corefile >/dev/null

  podman network connect --ip 192.168.20.2 work_net dns

  print_info "Criando container adminsrv..."

  podman run -d --name adminsrv --hostname adminsrv.lab \
    --network admin_net --ip 192.168.10.10 \
    --dns 192.168.10.2 \
    -p 2210:22 \
    --cap-add NET_RAW \
    projeto-iac/base:latest >/dev/null

  podman network connect --ip 192.168.30.10 data_net adminsrv

  print_info "Criando container worksrv..."

  podman run -d --name worksrv --hostname worksrv.lab \
    --network work_net --ip 192.168.20.10 \
    --dns 192.168.20.2 \
    -p 2220:22 \
    --cap-add NET_RAW \
    projeto-iac/base:latest >/dev/null

  podman network connect --ip 192.168.30.20 data_net worksrv

  print_info "Criando container datastore..."

  podman run -d --name datastore --hostname datastore.lab \
    --network data_net --ip 192.168.30.30 \
    -p 2230:22 \
    --cap-add NET_RAW \
    projeto-iac/base:latest >/dev/null

  print_info "Criando container client..."

  podman run -d --name client --hostname client.lab \
    --network admin_net --ip 192.168.10.100 \
    --dns 192.168.10.2 \
    -p 2240:22 \
    --cap-add NET_RAW \
    projeto-iac/base:latest >/dev/null

  podman network connect --ip 192.168.20.100 work_net client

  echo ""
  echo "  Containers criados:"
  echo "  - dns        : DNS interno"
  echo "  - adminsrv   : servidor administrativo"
  echo "  - worksrv    : servidor operacional"
  echo "  - datastore  : servidor de dados"
  echo "  - client     : máquina cliente"

  print_ok "Containers criados com sucesso"
}

show_containers() {
  print_info "Aguardando inicialização dos containers..."
  sleep 8

  echo ""
  echo -e "${BOLD}Containers em execução:${NC}"
  podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

  echo ""
  echo -e "${BOLD}Redes criadas:${NC}"
  podman network ls | grep -E "admin_net|work_net|data_net" || true
}

run_ansible() {
  print_info "Executando playbook Ansible..."

  cd "$PROJECT_DIR/ansible"

  ansible-playbook -i inventory playbook.yml

  print_ok "Ansible executado com sucesso"
}

run_tests() {
  print_info "Executando testes automatizados..."

  cd "$PROJECT_DIR/scripts"

  chmod +x test.sh
  ./test.sh

  print_ok "Testes finalizados"
}

show_credentials() {
  echo -e "\n${GREEN}${BOLD}============================================================${NC}"
  echo -e "${GREEN}${BOLD}   Ambiente pronto! Credenciais de acesso                  ${NC}"
  echo -e "${GREEN}${BOLD}============================================================${NC}"
  echo ""
  echo "  SSH:"
  echo "  - adminsrv   : ssh -p 2210 alice@localhost    senha: Alice@2024!"
  echo "  - worksrv    : ssh -p 2220 bob@localhost      senha: Bob@2024!"
  echo "  - worksrv    : ssh -p 2220 carol@localhost    senha: Carol@2024!"
  echo "  - datastore  : ssh -p 2230 alice@localhost    senha: Alice@2024!"
  echo "  - client     : ssh -p 2240 alice@localhost    senha: Alice@2024!"
  echo ""
  echo "  Testes manuais úteis:"
  echo "  - podman ps"
  echo "  - podman network ls"
  echo "  - podman exec client ip -4 addr"
  echo "  - podman exec client ping -c 2 192.168.10.10"
  echo "  - podman exec client ping -c 2 192.168.20.10"
  echo ""
}

print_header

print_step "1/7" "Validando diretório do projeto"
check_project_root

print_step "2/7" "Verificando dependências"
install_dependencies

print_step "3/7" "Limpando ambiente anterior"
cleanup_environment

print_step "4/7" "Criando imagens"
build_images

print_step "5/7" "Criando redes virtuais"
create_networks

print_step "6/7" "Criando containers"
create_containers
show_containers

print_step "7/7" "Executando Ansible e testes"
run_ansible
run_tests

show_credentials
