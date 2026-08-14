# GWOS — Instalação modular

Cada servidor do GWOS virou um módulo independente. Você pode instalar só o
DNS numa máquina, só o proxy em outra, ou todos no mesmo gateway — o resultado
é o mesmo de antes, mas dá para montar por partes.

```bash
# Tudo, na ordem (equivale ao instalador antigo)
bash modulos/instalar-todos.sh

# Um servidor isolado
bash modulos/20-dns-bind9/instalar.sh

# Conferir o que está instalado
bash modulos/verificar-todos.sh
```

---

## Os módulos

| Pasta | Serviço | O que instala |
|-------|---------|---------------|
| `00-base` | — | Firmware, microcode, `/etc/network/interfaces`, `ip_forward`, estado compartilhado |
| `10-banco-mariadb` | `mariadb` | Banco `gwos`, usuário, schema, credenciais em `/etc/gwos/db.conf` |
| `20-dns-bind9` | `named` | DNS recursivo da LAN, RPZ (bloqueio por domínio), forward zones do governo |
| `25-dns-interno-dnsmasq` | `gwos-dnsmasq` | Nomes internos da LAN em `127.0.0.1:5353` |
| `30-hora-chrony` | `chrony` | Servidor de hora (NTP) para o gateway e para a LAN |
| `40-firewall-nftables` | `nftables` | Firewall, NAT/masquerade e os redirecionamentos de proxy e DNS |
| `50-proxy-squid` | `squid` | Proxy 3127/3128/3129, SSL Bump e a CA |
| `60-painel-web` | `nginx`, `php8.4-fpm` | Painel, comando `gwos`, sudoers e cron |

Ordem recomendada: a numérica. Só há uma dependência dura — o **60-painel-web
exige o 10-banco-mariadb**. Todo o resto é opcional.

---

## Como cada módulo funciona sozinho

Nenhum módulo depende do instalador para descobrir a rede. Quem precisa saber
qual é a LAN, a rede ou o domínio interno lê `/etc/gwos/gwos.conf`; se o
arquivo não existir, `modulos/comum/lib.sh` detecta tudo a partir do sistema
(rota padrão, IPs das interfaces) e o cria — **sem tocar em
`/etc/network/interfaces`**. Só o `00-base` reconfigura a rede de verdade.

O que cada um faz quando é o único instalado:

- **20-dns-bind9** — resolver completo para a LAN. Bloqueio por domínio
  editando `/etc/bind/db.rpz.gwos` à mão.
- **25-dns-interno** — responde nomes internos em `127.0.0.1:5353`
  (`dig @127.0.0.1 -p 5353 samba.cdpni.local`). A LAN só alcança esses nomes
  com o BIND9 junto.
- **30-hora-chrony** — servidor NTP funcional para a LAN, inclusive com a
  internet fora (`local stratum 10`).
- **40-firewall-nftables** — gateway com NAT e firewall; a LAN navega direto,
  sem proxy.
- **50-proxy-squid** — proxy explícito na porta 3127. Sem o painel, as listas
  de grupos ficam vazias e a regra `http_access deny all` bloqueia todo mundo;
  o instalador mostra a linha a trocar para liberar a LAN.
- **10-banco** e **60-painel** — precisam um do outro; os demais são opcionais.

---

## Como eles se encontram

Cada módulo, ao terminar, roda `gwos-integrar` (instalado em
`/usr/local/sbin/`). Esse script olha o que existe na máquina naquele momento
e reescreve **só os pontos de contato**:

| Ponto de contato | Arquivo gerado | Condição |
|------------------|----------------|----------|
| BIND9 → upstream | `/etc/bind/named.conf.gwos-forwarders` | lista de `DNS_FORWARDERS` do `gwos.conf` |
| BIND9 → dnsmasq | `/etc/bind/named.conf.gwos-integracao` | domínio interno encaminhado só se o módulo 25 existir |
| Squid → resolver | `/etc/squid/conf.d/gwos_integracao.conf` | `127.0.0.1` com BIND9; resolvers externos sem ele |
| Squid → redes | `/etc/squid/conf.d/gwos_redes.conf` | ACLs vindas de `gwos.conf` (cobre faixas fora do RFC 1918) |
| nftables | `/etc/nftables.conf` | redireciona 80/443 só se houver Squid; DNS só se houver BIND9 |
| chrony | `/etc/chrony/conf.d/gwos.conf` | fontes de `NTP_SERVIDORES`/`NTP_POOL` + libera as redes internas atuais |

Por isso a ordem não trava nada: instale o Squid depois do firewall e o
firewall se reajusta sozinho; remova o Squid e os redirecionamentos somem
antes que a LAN fique sem internet.

Estado e registro:

```
/etc/gwos/gwos.conf        parâmetros de rede compartilhados
/etc/gwos/db.conf          credenciais do banco (0600)
/etc/gwos/modulos.d/<nome> um arquivo por módulo instalado
/etc/gwos/lib.sh           cópia da biblioteca comum
/usr/local/sbin/gwos-integrar        re-costura tudo
/usr/local/sbin/gwos-definir         altera uma chave do gwos.conf, com validação
/usr/local/sbin/gwos-zona            zonas de encaminhamento do BIND9
/usr/local/sbin/gwos-gerar-nftables  regera o firewall
/usr/local/sbin/gwos-gerar-dnsmasq   regera o dnsmasq
/usr/local/sbin/gwos-senha-padrao    senha inicial do painel
```

O `gwos-definir` é o único caminho de escrita que o painel web tem no
`gwos.conf`: lista fechada de chaves, validador por chave, e `gwos-integrar` no
final. Interfaces, IP do gateway e rede ficam de fora de propósito — trocar IP
é `gwos ip`, que valida com `ifquery` e põe o IP novo antes de tirar o antigo.

```bash
gwos-definir --listar
gwos-definir DNS_FORWARDERS "8.8.8.8 1.1.1.1"
```

---

## Comandos por módulo

Todo módulo tem os mesmos três scripts:

```bash
bash modulos/<modulo>/instalar.sh      # instala e integra
bash modulos/<modulo>/verificar.sh     # diagnostica (sai 1 se houver problema)
bash modulos/<modulo>/desinstalar.sh   # remove e reintegra o que sobrou
```

Alguns aceitam opções:

```bash
bash modulos/10-banco-mariadb/instalar.sh --recriar   # zera o banco
bash modulos/instalar-todos.sh --pular 00-base        # tudo menos a rede
bash modulos/instalar-todos.sh 20-dns-bind9 50-proxy-squid
bash modulos/verificar-todos.sh --todos
```

---

## Copiar um módulo para outra máquina

Leve a pasta do módulo **e a pasta `comum/`** — é lá que está a biblioteca:

```bash
scp -r modulos/comum modulos/20-dns-bind9 root@outra-maquina:/tmp/gwos-dns/
ssh root@outra-maquina 'bash /tmp/gwos-dns/20-dns-bind9/instalar.sh'
```

Dois módulos precisam do repositório completo: o `10-banco-mariadb`
(`database/schema.sql`) e o `60-painel-web` (`app/`, `public/`, `scripts/`).

---

## Reinstalar / reaplicar

Os instaladores são reexecutáveis. O que é preservado numa reinstalação:

- banco de dados (a menos de `--recriar`)
- CA do SSL Bump (os clientes não precisam reinstalar o certificado)
- zona RPZ com os bloqueios já aplicados
- senha do painel, se já tiver sido trocada

O que é sempre regravado: `squid.conf`, `named.conf.*`, `/etc/nftables.conf`,
`/etc/dnsmasq.d/gwos.conf` e a configuração do Nginx — com backup `.bak.<data>`
quando o arquivo já existia.
