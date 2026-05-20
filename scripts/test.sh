#!/bin/bash
# =============================================================================
# SCRIPT DE TESTES — Infraestrutura Corporativa
# Valida: redes, DNS, SSH, permissões e isolamento
# Executar a partir do host WSL após o ambiente estar no ar
# =============================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

# Função auxiliar: exibe resultado do teste
resultado() {
    if [ $1 -eq 0 ]; then
        echo -e "  ${GREEN}[PASS]${NC} $2"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} $2"
        ((FAIL++))
    fi
}

# Opções SSH padrão (desabilita verificação de chave em lab)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   TESTES DE INFRAESTRUTURA — CONTAINERS + ANSIBLE         ${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# ============================================================================
# BLOCO 1: TESTE DE CONTAINERS ATIVOS
# ============================================================================
echo -e "${YELLOW}[1/5] VERIFICANDO CONTAINERS${NC}"

for container in dns adminsrv worksrv datastore client; do
    podman inspect --format='{{.State.Running}}' $container 2>/dev/null | grep -q "true"
    resultado $? "Container '$container' está em execução"
done

echo ""

# ============================================================================
# BLOCO 2: TESTES DE REDE — Ping entre hosts autorizados
# ============================================================================
echo -e "${YELLOW}[2/5] TESTES DE CONECTIVIDADE (PING)${NC}"

# client → adminsrv (mesma rede admin_net) — DEVE funcionar
podman exec client ping -c 1 -W 2 192.168.10.10 > /dev/null 2>&1
resultado $? "client → adminsrv (admin_net: 192.168.10.10)"

# client → worksrv (mesma rede work_net) — DEVE funcionar
podman exec client ping -c 1 -W 2 192.168.20.10 > /dev/null 2>&1
resultado $? "client → worksrv (work_net: 192.168.20.10)"

# adminsrv → datastore (data_net) — DEVE funcionar
podman exec adminsrv ping -c 1 -W 2 192.168.30.30 > /dev/null 2>&1
resultado $? "adminsrv → datastore (data_net: 192.168.30.30)"

# worksrv → datastore (data_net) — DEVE funcionar
podman exec worksrv ping -c 1 -W 2 192.168.30.30 > /dev/null 2>&1
resultado $? "worksrv → datastore (data_net: 192.168.30.30)"

# ISOLAMENTO: client → datastore (redes diferentes) — DEVE FALHAR
podman exec client ping -c 1 -W 2 192.168.30.30 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "  ${GREEN}[PASS]${NC} ISOLAMENTO: client não acessa datastore (192.168.30.30) ✓"
    ((PASS++))
else
    echo -e "  ${RED}[FAIL]${NC} ISOLAMENTO: client conseguiu pingar datastore — verificar segmentação!"
    ((FAIL++))
fi

# ISOLAMENTO: adminsrv → worksrv (redes diferentes) — DEVE FALHAR
podman exec adminsrv ping -c 1 -W 2 192.168.20.10 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "  ${GREEN}[PASS]${NC} ISOLAMENTO: adminsrv não acessa work_net (192.168.20.10) ✓"
    ((PASS++))
else
    echo -e "  ${RED}[FAIL]${NC} ISOLAMENTO: adminsrv acessou work_net — verificar segmentação!"
    ((FAIL++))
fi

echo ""

# ============================================================================
# BLOCO 3: TESTES DE DNS
# ============================================================================
echo -e "${YELLOW}[3/5] TESTES DE RESOLUÇÃO DNS${NC}"

# Nomes que o DNS interno deve resolver
declare -A dns_map
dns_map["adminsrv.lab"]="192.168.10.10"
dns_map["worksrv.lab"]="192.168.20.10"
dns_map["dns.lab"]="192.168.10.2"
dns_map["datastore.lab"]="192.168.30.30"
dns_map["client.lab"]="192.168.10.100"

for nome in "${!dns_map[@]}"; do
    ip_esperado="${dns_map[$nome]}"
    ip_resolvido=$(podman exec client nslookup "$nome" 192.168.10.2 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
    if [ "$ip_resolvido" = "$ip_esperado" ]; then
        echo -e "  ${GREEN}[PASS]${NC} DNS: $nome → $ip_resolvido"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} DNS: $nome → esperado $ip_esperado, obtido '$ip_resolvido'"
        ((FAIL++))
    fi
done

echo ""

# ============================================================================
# BLOCO 4: TESTES SSH E USUÁRIOS
# ============================================================================
echo -e "${YELLOW}[4/5] TESTES SSH E AUTENTICAÇÃO DE USUÁRIOS${NC}"

# alice (administradora) deve acessar adminsrv
sshpass -p "Alice@2024!" ssh $SSH_OPTS -p 2210 alice@localhost "echo OK" > /dev/null 2>&1
resultado $? "SSH: alice@adminsrv (administradora)"

# bob (operador) deve acessar worksrv
sshpass -p "Bob@2024!" ssh $SSH_OPTS -p 2220 bob@localhost "echo OK" > /dev/null 2>&1
resultado $? "SSH: bob@worksrv (operador)"

# carol (convidada) deve acessar worksrv mas com shell restrito
sshpass -p "Carol@2024!" ssh $SSH_OPTS -p 2220 carol@localhost "echo OK" > /dev/null 2>&1
resultado $? "SSH: carol@worksrv (convidada, shell restrito)"

echo ""

# ============================================================================
# BLOCO 5: TESTES DE PERMISSÕES
# ============================================================================
echo -e "${YELLOW}[5/5] TESTES DE PERMISSÕES EM DIRETÓRIOS${NC}"

# alice pode ler /admin
sshpass -p "Alice@2024!" ssh $SSH_OPTS -p 2210 alice@localhost "ls /admin" > /dev/null 2>&1
resultado $? "alice pode listar /admin"

# alice pode ler /operacao
sshpass -p "Alice@2024!" ssh $SSH_OPTS -p 2210 alice@localhost "ls /operacao" > /dev/null 2>&1
resultado $? "alice pode listar /operacao"

# bob pode ler /operacao
sshpass -p "Bob@2024!" ssh $SSH_OPTS -p 2220 bob@localhost "ls /operacao" > /dev/null 2>&1
resultado $? "bob pode listar /operacao"

# bob NÃO deve poder ler /admin
sshpass -p "Bob@2024!" ssh $SSH_OPTS -p 2220 bob@localhost "ls /admin" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "  ${GREEN}[PASS]${NC} BLOQUEIO: bob não pode acessar /admin ✓"
    ((PASS++))
else
    echo -e "  ${RED}[FAIL]${NC} BLOQUEIO: bob conseguiu acessar /admin!"
    ((FAIL++))
fi

# carol pode ler /publico
sshpass -p "Carol@2024!" ssh $SSH_OPTS -p 2220 carol@localhost "ls /publico" > /dev/null 2>&1
resultado $? "carol pode listar /publico"

# alice tem sudo
sshpass -p "Alice@2024!" ssh $SSH_OPTS -p 2210 alice@localhost "sudo whoami" > /dev/null 2>&1
resultado $? "alice tem acesso sudo"

# bob NÃO deve ter sudo geral
sshpass -p "Bob@2024!" ssh $SSH_OPTS -p 2220 bob@localhost "sudo whoami" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "  ${GREEN}[PASS]${NC} BLOQUEIO: bob não tem sudo geral ✓"
    ((PASS++))
else
    echo -e "  ${RED}[FAIL]${NC} BLOQUEIO: bob tem sudo geral — verificar sudoers!"
    ((FAIL++))
fi

# ============================================================================
# RESUMO FINAL
# ============================================================================
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}                     RESUMO DOS TESTES                     ${NC}"
echo -e "${BLUE}============================================================${NC}"
echo -e "  ${GREEN}PASSOU: $PASS${NC}"
echo -e "  ${RED}FALHOU: $FAIL${NC}"
TOTAL=$((PASS + FAIL))
echo -e "  Total:  $TOTAL testes"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}  ✅ Todos os testes passaram! Infraestrutura OK.${NC}"
else
    echo -e "${YELLOW}  ⚠️  $FAIL teste(s) falharam. Verifique a configuração.${NC}"
fi
echo ""
