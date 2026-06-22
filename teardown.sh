#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${BLUE}${BOLD}============================================================${NC}"
echo -e "${BLUE}${BOLD}   INFRAESTRUTURA CORPORATIVA — Limpeza (Teardown)         ${NC}"
echo -e "${BLUE}${BOLD}   github.com/RainerJustiniano/projeto-iac                 ${NC}"
echo -e "${BLUE}${BOLD}============================================================${NC}"

echo -e "\n${YELLOW}[1/2] Parando e removendo containers...${NC}"
podman rm -f dns adminsrv worksrv datastore client 2>/dev/null
echo -e "  ${GREEN}✓${NC} Containers removidos"

echo -e "\n${YELLOW}[2/2] Removendo redes...${NC}"
podman network rm -f admin_net work_net data_net 2>/dev/null
podman network rm -f projeto-iac_admin_net projeto-iac_work_net projeto-iac_data_net 2>/dev/null
echo -e "  ${GREEN}✓${NC} Redes removidas"

echo -e "\n${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}   Infraestrutura removida com sucesso.                    ${NC}"
echo -e "${GREEN}${BOLD}   Para recriar do zero, rode: bash setup.sh               ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
