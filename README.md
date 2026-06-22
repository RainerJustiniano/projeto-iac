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
10. [Testes Automatizados](#testes-automatizados)
11. [Limitações Conhecidas](#limitações-conhecidas)
12. [Troubleshooting](#troubleshooting)

---

## Visão Geral

Este projeto implementa uma **mini infraestrutura corporativa reproduzível por código** (*Infrastructure as Code — IaC*), utilizando **Podman**, **Ansible** e **CoreDNS**. O ambiente simula uma empresa com dois segmentos de rede isolados — Administrativo e Operacional — além de um servidor de dados centralizado.

**Tecnologias utilizadas:**

| Tecnologia | Versão | Função |
|---|---|---|
| Podman | 4.x+ | Criação e execução dos containers (sem precisar de Docker Desktop) |
| Ansible | 2.x+ | Automação de configuração (usuários, permissões, diretórios) |
| CoreDNS | 1.11.1 | Servidor DNS interno |
| Ubuntu | 22.04 | Sistema base dos containers |

> **Por que Podman?** No ambiente de desenvolvimento usado (Windows + WSL com pouco espaço em disco), o Podman foi escolhido por não exigir o Docker Desktop instalado.

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
- `Service A → Data Store X` (Read): adminsrv acessa /datastore/readonly via usuário de serviço `ds_reader`
- `Service B → Data Store X` (Read/Write): worksrv acessa /datastore/readwrite via usuário de serviço `ds_writer`

---

## Pré-requisitos

### No Windows com WSL Ubuntu

```bash
# 1. Instalar WSL Ubuntu (PowerShell como Administrador, no Windows)
wsl --install -d Ubuntu

# 2. Dentro do WSL Ubuntu, instalar Podman e dependências
sudo apt update
sudo apt install -y podman ansible sshpass git

# 3. Verificar instalação
podman --version
ansible --version
```

---

## Estrutura do Projeto

```
projeto-iac/
│
├── setup.sh                     # Script único: builda, sobe, configura e testa tudo (Podman)
├── teardown.sh                  # Para e remove todos os containers e redes
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
│       │   ├── handlers/main.yml
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

Um único comando builda as imagens, cria as redes, sobe os 5 containers, roda o Ansible e executa os testes:

```bash
git clone https://github.com/RainerJustiniano/projeto-iac.git
cd projeto-iac
bash setup.sh
```

Ao final você verá as credenciais de acesso SSH no terminal. Para refazer tudo do zero, basta rodar `bash setup.sh` novamente — o script remove containers e redes anteriores antes de recriar.

> **Por que não usar `podman-compose`?** A versão 1.0.6 do `podman-compose` tem um bug conhecido: ela aplica a flag `--ip` em **todas** as redes de um container simultaneamente, mesmo quando você só define IP fixo em uma rede. Isso quebra qualquer container conectado a mais de uma rede (erro `--ip can only be set for a single network`). O `setup.sh` contorna isso criando cada container com `podman run` e conectando as redes extras depois, via `podman network connect`.

### Rodando o Ansible manualmente (opcional, já incluso no setup.sh)

```bash
cd ansible/
ansible all -i inventory -m ping
ansible-playbook -i inventory playbook.yml
```

### Rodando os testes manualmente (opcional, já incluso no setup.sh)

```bash
cd scripts/
chmod +x test.sh
./test.sh
```

### Parando e removendo tudo

Quando terminar de usar a infraestrutura (ex.: depois da apresentação, ou pra liberar recursos da máquina), use o `teardown.sh` em vez de remover containers um por um manualmente:

```bash
bash teardown.sh
```

Isso para e remove os 5 containers e as 3 redes (`admin_net`, `work_net`, `data_net`). As imagens já buildadas (`projeto-iac/base`, `coredns/coredns`) **não são removidas** — assim, rodar `bash setup.sh` de novo é rápido, sem precisar rebuildar do zero.

> Se quiser só **pausar** sem remover (pra religar depois sem rebuildar nada), use `podman stop dns adminsrv worksrv datastore client` e depois `podman start` nos mesmos nomes — mais rápido que remover e recriar.

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

> **Nota técnica:** a imagem oficial `coredns/coredns` é construída `FROM scratch` (sem shell, sem `$PATH`) e o binário fica em `/coredns`. Por isso o `Dockerfile` em `containers/dns/` usa `ENTRYPOINT ["/coredns"]` com caminho absoluto — usar apenas `"coredns"` falha com `executable file not found in $PATH`.

### Testar manualmente

```bash
podman exec -it client bash

nslookup adminsrv.lab 192.168.10.2
nslookup worksrv.lab 192.168.10.2
nslookup datastore.lab 192.168.10.2

dig @192.168.10.2 adminsrv.lab
```

---

## Automação com Ansible

O Ansible automatiza **toda** a configuração dos servidores sem intervenção manual. Três roles compõem o playbook, executadas em ordem: `users` → `permissions` → `directories`.

### Role: users

Cria grupos e usuários com shells e senhas corretos.

| Usuário | Grupo | Shell | Função |
|---|---|---|---|
| `alice` | administradores | /bin/bash | Administradora — acesso total |
| `bob` | operadores | /bin/bash | Operador — acesso restrito |
| `carol` | convidados | /bin/rbash | Convidada — leitura apenas |

> O filtro `password_hash()` usado para gerar os hashes SHA-512 roda na **máquina de controle** (seu WSL), não no container remoto — é por isso que não há instalação de `passlib` dentro dos containers.

### Role: permissions

Configura o `/etc/sudoers.d/` por grupo:

| Grupo | Permissão Sudo |
|---|---|
| administradores | `ALL=(ALL:ALL) NOPASSWD: ALL` |
| operadores | Apenas `/operacao/scripts/*.sh` |
| convidados | Nenhuma |

Também cria, somente no container `datastore`, os usuários de serviço `ds_reader` (grupo operadores) e `ds_writer` (grupo administradores), que representam o Service A e o Service B do diagrama acessando o Data Store X.

### Role: directories

Cria a estrutura de diretórios corporativos com ACLs:

| Diretório | Dono | Grupo | Modo | Descrição |
|---|---|---|---|---|
| `/admin` | root | administradores | `0770` | Somente admins |
| `/operacao` | root | administradores | `0750` + ACL | Admins + Operadores |
| `/publico` | root | root | `1777` | Todos (sticky bit) |
| `/datastore/readonly` | root | operadores | `0750` + ACL | Leitura — `ds_reader` |
| `/datastore/readwrite` | root | administradores | `0770` + ACL | Escrita — `ds_writer` |

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
alice@adminsrv:~$ sudo whoami                       → root  (permitido)
bob@worksrv:~$ sudo whoami                          → erro  (negado)
bob@worksrv:~$ sudo /operacao/scripts/status.sh      → OK   (permitido)
```

---

## Testes Automatizados

O `scripts/test.sh` valida 6 blocos: containers ativos, conectividade/isolamento de rede, resolução DNS, SSH e autenticação, permissões de diretório e os usuários de serviço do Data Store X (`ds_reader`/`ds_writer`).

```bash
cd scripts/
./test.sh
```

Resultado esperado: **24 de 26 testes passam**. Os 2 que falham são esperados — veja a seção abaixo.

---

## Limitações Conhecidas

### Isolamento ICMP entre redes não autorizadas

Para que o `ping` funcionasse entre redes **autorizadas** (ex.: client → adminsrv), foi necessário adicionar a capability `--cap-add NET_RAW` aos containers no Podman rootless. Essa capability também permite ICMP entre redes que deveriam estar isoladas (ex.: client → datastore), fazendo 2 dos 26 testes do `test.sh` falharem.

**O isolamento real (TCP/UDP) continua funcionando** — apenas o protocolo ICMP (usado pelo `ping`) é afetado. Em um ambiente de produção, esse cenário seria resolvido com regras de firewall (`iptables`/`nftables`) explícitas, independentes da capability de rede do container.

---

## Troubleshooting

### Podman não encontrado no WSL

```bash
sudo apt update
sudo apt install -y podman
```

### Ansible falha com "to use the 'ssh' connection type... you must install the sshpass program"

```bash
sudo apt install -y sshpass
```

### Ansible falha com "connection refused"

```bash
# Verificar se os containers estão de pé
podman ps

# Verificar se as portas estão abertas
ss -tlnp | grep -E "2210|2220|2230|2240"

# Aguardar containers iniciarem completamente antes do Ansible
sleep 8 && ansible all -i ansible/inventory -m ping
```

### Erro de autenticação SSH (senha não aceita)

Confirme que está digitando exatamente `Alice@2024!` (A maiúsculo, arroba, exclamação) — teclados em PT-BR às vezes trocam esses caracteres especiais. Teste sem digitar manualmente:

```bash
sshpass -p "Alice@2024!" ssh -o StrictHostKeyChecking=no -p 2210 alice@localhost "whoami"
```

### Erro "executable file 'coredns' not found in \$PATH"

Esse erro ocorre se você reconstruir a imagem DNS a partir do `Dockerfile` antigo. A versão atual já está corrigida (`ENTRYPOINT ["/coredns"]`, caminho absoluto). Se aparecer, confirme que está usando a versão mais recente do repositório (`git pull`).

### Parar e limpar o ambiente (Podman)

```bash
bash teardown.sh
```

Veja mais detalhes na seção [Parando e removendo tudo](#parando-e-removendo-tudo).

### Refazer tudo do zero

```bash
bash setup.sh
```

---

*Projeto desenvolvido para a disciplina de Conteinerização e Orquestração — IFMT Campus Cuiabá*
