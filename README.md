# Infraestrutura Automatizada com Containers e Ansible

**Instituto Federal de Mato Grosso — Campus Cuiabá**
Disciplina: Conteinerização e Orquestração

---

## Sumário

1. [Visão Geral](#visão-geral)
2. [Arquitetura da Infraestrutura](#arquitetura-da-infraestrutura)
3. [Mapeamento do Diagrama (Ilograph)](#mapeamento-do-diagrama-ilograph)
4. [Pré-requisitos](#pré-requisitos)
5. [Estrutura do Projeto](#estrutura-do-projeto)
6. [Como Executar](#como-executar)
7. [Configuração DNS (CoreDNS)](#configuração-dns-coredns)
8. [Automação com Ansible](#automação-com-ansible)
9. [Permissões e Controle de Acesso](#permissões-e-controle-de-acesso)
10. [Testes Obrigatórios](#testes-obrigatórios)
11. [Troubleshooting](#troubleshooting)

---

## Visão Geral

Este projeto implementa uma **mini infraestrutura corporativa reproduzível por código** (*Infrastructure as Code — IaC*), utilizando Docker, Docker Compose e Ansible. O ambiente simula uma empresa com dois segmentos de rede isolados: Administrativo e Operacional, além de um servidor de dados centralizado.

**Tecnologias utilizadas:**

| Tecnologia | Versão | Função |
|---|---|---|
| Docker | 24+ | Criação e execução dos containers |
| Docker Compose | v2 | Orquestração dos containers |
| Ansible | 2.15+ | Automação de configuração |
| CoreDNS | 1.11.1 | Servidor DNS interno |
| Ubuntu | 22.04 | Sistema base dos containers |

---

## Arquitetura da Infraestrutura

```
                        +-------------------+
                        |    DNS Server     |
                        |    dns.lab        |
                        | 10.2 | 20.2       |
                        +---+----------+----+
                            |          |
              admin_net     |          |    work_net
           192.168.10.0/24  |          | 192.168.20.0/24
                            |          |
     +----------+-----------+          +-----------+---------+
     |          |                                  |         |
+----+------+   +----------+          +------------+  +------+----+
| adminsrv  |   |  client  |          |   worksrv  |  |  client   |
| .10.10    |   |  .10.100 |          |   .20.10   |  |  .20.100  |
| SSH+sudo  |   | (testes) |          |  acesso web|  | (testes)  |
+----+------+   +----------+          +------+-----+  +------+----+
     |                                       |
     |         data_net 192.168.30.0/24      |
     |                                       |
     +----------------+----------------------+
                      |
               +------+-------+
               |  datastore   |
               |  .30.30      |
               | Data Store X |
               +--------------+

Legenda:
  adminsrv → datastore: LEITURA (Service A → Read)
  worksrv  → datastore: LEITURA e ESCRITA (Service B → Read/Write)
  client   → adminsrv: USO (Users → Service A)
  client   → worksrv:  USO (Users → Service B)
```

---

## Mapeamento do Diagrama (Ilograph)

O diagrama Ilograph fornecido foi mapeado para componentes reais de infraestrutura:

| Recurso Ilograph | Container | Função | Rede(s) |
|---|---|---|---|
| **Users** | `client` | Máquina cliente para testes | admin_net + work_net |
| **Service A** | `adminsrv` | Servidor Administrativo (SSH + sudo) | admin_net + data_net |
| **Service B** | `worksrv` | Servidor Operacional (web + restrito) | work_net + data_net |
| **Data Store X** | `datastore` | Servidor de Dados Corporativos | data_net |
| *(Infraestrutura)* | `dns` | Servidor DNS Interno (CoreDNS) | admin_net + work_net |

**Relações implementadas:**

- `Users → Service A` (Use): client acessa adminsrv via SSH na admin_net
- `Users → Service B` (Use): client acessa worksrv via SSH na work_net
- `Service A → Data Store X` (Read): adminsrv acessa /datastore/readonly
- `Service B → Data Store X` (Read/Write): worksrv acessa /datastore/readwrite

---

## Pré-requisitos

### No Windows com WSL Ubuntu

```bash
# 1. Instalar Docker Desktop (Windows)
# Baixar em: https://www.docker.com/products/docker-desktop/
# Habilitar integração com WSL2 nas configurações do Docker Desktop

# 2. No terminal WSL Ubuntu, verificar se Docker está disponível:
docker --version
docker compose version

# 3. Instalar Ansible no WSL Ubuntu
sudo apt update
sudo apt install -y ansible sshpass python3-pip

# 4. Verificar versão do Ansible
ansible --version
```

---

## Estrutura do Projeto

```
projeto-iac/
│
├── docker-compose.yml          # Orquestração dos containers e redes
│
├── containers/
│   ├── base/
│   │   └── Dockerfile          # Imagem base Ubuntu 22.04 com SSH
│   └── dns/
│       ├── Dockerfile          # Imagem CoreDNS com configs
│       ├── Corefile            # Configuração principal do CoreDNS
│       └── hosts               # Mapeamento nome → IP interno
│
├── ansible/
│   ├── inventory               # Lista de hosts gerenciados
│   ├── playbook.yml            # Playbook principal de configuração
│   └── roles/
│       ├── users/              # Criação de grupos e usuários
│       │   ├── tasks/main.yml
│       │   └── vars/main.yml
│       ├── permissions/        # Sudo e controle de acesso
│       │   └── tasks/main.yml
│       └── directories/        # Diretórios corporativos + ACLs
│           └── tasks/main.yml
│
├── scripts/
│   └── test.sh                 # Bateria de testes automatizados
│
└── README.md                   # Esta documentação
```

---

## Como Executar

### Passo 1 — Construir e subir os containers

```bash
# Na raiz do projeto (onde está o docker-compose.yml)
cd projeto-iac/

# Constrói as imagens e sobe todos os containers
docker compose up -d --build

# Verificar se todos estão rodando
docker compose ps
```

Saída esperada:
```
NAME         STATUS    PORTS
adminsrv     running   0.0.0.0:2210->22/tcp
client       running   0.0.0.0:2240->22/tcp
datastore    running   0.0.0.0:2230->22/tcp
dns          running
worksrv      running   0.0.0.0:2220->22/tcp
```

### Passo 2 — Executar o Playbook Ansible

```bash
# A partir do diretório ansible/
cd ansible/

# Testar conectividade com todos os hosts
ansible all -i inventory -m ping

# Executar o playbook completo
ansible-playbook -i inventory playbook.yml

# Executar com saída detalhada (verbose)
ansible-playbook -i inventory playbook.yml -v
```

### Passo 3 — Executar os testes

```bash
# Instalar dependência sshpass (necessário para testes SSH)
sudo apt install -y sshpass

# Tornar o script executável (já configurado, mas por segurança)
chmod +x scripts/test.sh

# Executar todos os testes
./scripts/test.sh
```

---

## Configuração DNS (CoreDNS)

O **CoreDNS** foi escolhido por sua simplicidade: uma única configuração em texto (`Corefile`) substitui as múltiplas zonas e arquivos do BIND9.

### Como funciona

O arquivo `Corefile` define dois blocos de zona:

```
lab. { ... }   ← responde consultas para *.lab
. { ... }      ← redireciona o resto para 8.8.8.8
```

O plugin `hosts` funciona como um `/etc/hosts` centralizado para toda a rede:

```
192.168.10.10  adminsrv.lab
192.168.20.10  worksrv.lab
192.168.30.30  datastore.lab
192.168.10.2   dns.lab
```

### Testar manualmente

```bash
# A partir do container client
docker exec -it client bash

# Testar resolução DNS
nslookup adminsrv.lab 192.168.10.2
nslookup worksrv.lab 192.168.10.2
nslookup datastore.lab 192.168.10.2

# Ou usando dig
dig @192.168.10.2 adminsrv.lab
```

---

## Automação com Ansible

O Ansible automatiza **toda** a configuração dos servidores sem intervenção manual. Três roles compõem o playbook:

### Role: users

Cria grupos e usuários com shells e senhas corretos.

| Usuário | Grupo | Shell | Função |
|---|---|---|---|
| `alice` | administradores | /bin/bash | Administradora — acesso total |
| `bob` | operadores | /bin/bash | Operador — acesso restrito |
| `carol` | convidados | /bin/rbash | Convidada — leitura apenas |

### Role: permissions

Configura o `/etc/sudoers.d/` por grupo:

| Grupo | Permissão Sudo |
|---|---|
| administradores | `ALL=(ALL:ALL) NOPASSWD: ALL` |
| operadores | Apenas scripts em `/operacao/scripts/*.sh` |
| convidados | Nenhuma |

### Role: directories

Cria a estrutura de diretórios corporativos com ACLs:

| Diretório | Dono | Grupo | Modo | Descrição |
|---|---|---|---|---|
| `/admin` | root | administradores | `0770` | Somente admins |
| `/operacao` | root | administradores | `0750` + ACL | Admins + Operadores |
| `/publico` | root | root | `1777` | Todos (sticky bit) |
| `/datastore/readonly` | root | operadores | `0750` | Leitura — Service A |
| `/datastore/readwrite` | root | administradores | `0770` | Escrita — Service B |

---

## Permissões e Controle de Acesso

### Tabela de Permissões por Diretório

```
Diretório        alice(admin)  bob(operador)  carol(convidado)
/admin           rwx           ---            ---
/operacao        rwx           r-x            ---
/publico         rwx           rwx            rwx
/datastore/*     via serviço   via serviço    sem acesso
```

### Sudo

```
alice@adminsrv:~$ sudo whoami    → root  (permitido)
bob@worksrv:~$ sudo whoami       → erro  (negado)
bob@worksrv:~$ sudo /operacao/scripts/status.sh  → OK  (permitido)
```

---

## Testes Obrigatórios

### Testes de Rede

```bash
# Ping autorizado — mesma rede
docker exec client ping -c 3 192.168.10.10   # client → adminsrv ✓
docker exec client ping -c 3 192.168.20.10   # client → worksrv ✓

# Isolamento — redes diferentes
docker exec client ping -c 3 192.168.30.30   # client → datastore ✗ (bloqueado)
docker exec adminsrv ping -c 3 192.168.20.10 # admin_net → work_net ✗ (bloqueado)
```

### Testes DNS

```bash
docker exec client nslookup adminsrv.lab
# Esperado: 192.168.10.10

docker exec client nslookup worksrv.lab
# Esperado: 192.168.20.10

docker exec client nslookup datastore.lab
# Esperado: 192.168.30.30
```

### Testes SSH

```bash
# Login como administradora
ssh -p 2210 alice@localhost   # senha: Alice@2024!

# Login como operador
ssh -p 2220 bob@localhost     # senha: Bob@2024!

# Login como convidado
ssh -p 2220 carol@localhost   # senha: Carol@2024!
```

### Testes de Permissão

```bash
# Como alice — deve funcionar
ssh -p 2210 alice@localhost "ls /admin"
ssh -p 2210 alice@localhost "sudo whoami"

# Como bob — leitura OK, admin bloqueado
ssh -p 2220 bob@localhost "ls /operacao"
ssh -p 2220 bob@localhost "ls /admin"    # Deve retornar: Permission denied

# Como carol — apenas /publico
ssh -p 2220 carol@localhost "ls /publico"
ssh -p 2220 carol@localhost "ls /admin"  # Deve retornar: Permission denied
```

---

## Troubleshooting

### Docker não conecta no WSL

```bash
# Verificar se o Docker Desktop está rodando no Windows
# Nas configurações do Docker Desktop: Settings → Resources → WSL Integration
# Habilitar para a distro Ubuntu
```

### Ansible falha com "connection refused"

```bash
# Verificar se as portas estão abertas
ss -tlnp | grep 221

# Aguardar containers iniciarem completamente
docker compose up -d && sleep 10 && ansible all -i ansible/inventory -m ping
```

### Erro de autenticação SSH

```bash
# Testar conexão manual primeiro
ssh -o StrictHostKeyChecking=no -p 2210 root@localhost
# senha: Lab@2024!
```

### Parar e limpar o ambiente

```bash
# Para os containers
docker compose down

# Remove containers, redes e volumes
docker compose down -v --rmi local

# Rebuild completo
docker compose up -d --build --force-recreate
```

---

*Projeto desenvolvido para a disciplina de Conteinerização e Orquestração — IFMT Campus Cuiabá*
