FROM ubuntu:22.04

# Evita prompts interativos durante a instalação
ENV DEBIAN_FRONTEND=noninteractive

# Instala pacotes essenciais:
# - openssh-server: servidor SSH para acesso remoto e Ansible
# - sudo: controle de privilégios
# - iputils-ping: permite testes de conectividade (ping)
# - dnsutils: ferramentas DNS (nslookup, dig)
# - iproute2: comandos de rede (ip, ss)
# - net-tools: ferramentas de rede legadas (ifconfig, netstat)
# - python3: obrigatório para o Ansible operar no host remoto
# - curl: testes HTTP para o worksrv
# - acl: necessário para o módulo "acl" do Ansible (setfacl/getfacl) —
#   pré-instalado aqui para não reinstalar em toda execução do playbook
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    iputils-ping \
    dnsutils \
    iproute2 \
    net-tools \
    python3 \
    curl \
    vim \
    acl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Cria o diretório necessário para o daemon SSH
RUN mkdir /var/run/sshd

# Define senha root (apenas para ambiente de laboratório)
RUN echo 'root:Lab@2024!' | chpasswd

# Configura SSH:
# - PermitRootLogin yes: permite login como root (necessário para Ansible)
# - PasswordAuthentication yes: habilita autenticação por senha
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Cria diretórios corporativos padrão
RUN mkdir -p /admin /operacao /publico

# Expõe porta SSH
EXPOSE 22

# Inicia o daemon SSH em modo foreground (mantém o container ativo)
CMD ["/usr/sbin/sshd", "-D"]
