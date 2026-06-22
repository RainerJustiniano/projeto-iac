FROM docker.io/coredns/coredns:1.11.1

# Copia o arquivo de configuração principal do CoreDNS
COPY Corefile /etc/coredns/Corefile

# Copia o arquivo de hosts internos (mapeamento nome → IP)
COPY hosts /etc/coredns/hosts

# Expõe porta DNS (UDP e TCP)
EXPOSE 53/udp
EXPOSE 53/tcp

# Inicia o CoreDNS apontando para o Corefile
# IMPORTANTE: a imagem base é "FROM scratch" — não tem $PATH nem shell.
# O binário fica em /coredns (caminho absoluto), por isso o ENTRYPOINT
# precisa apontar para "/coredns" e não para "coredns" (que falharia
# com "executable file not found in $PATH").
ENTRYPOINT ["/coredns"]
CMD ["-conf", "/etc/coredns/Corefile"]
