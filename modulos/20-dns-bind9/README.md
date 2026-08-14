# 20-dns-bind9 — servidor DNS da rede

BIND9 como resolver recursivo da LAN, com bloqueio de domínios por RPZ.

## O que faz

- Instala `bind9`, `bind9-utils` e `dnsutils`
- `named.conf.options`: forwarders públicos, `allow-query { localhost; localnets; }`
  (sobrevive a trocas de IP) e a diretiva **`response-policy`** que ativa a RPZ
- `named.conf.local`: zona RPZ, forward zones dos DNS internos do governo e o
  `include` do arquivo de integração
- Cria `/var/log/named` e aponta `/etc/resolv.conf` do gateway para `127.0.0.1`

> **Correção em relação ao instalador antigo:** a zona `rpz.gwos` era
> declarada mas nunca ativada — faltava `response-policy` em
> `named.conf.options`, então o bloqueio de domínios por DNS não surtia
> efeito. Agora está ativo.

## Instalação

```bash
bash instalar.sh
```

## Sozinho

Resolver completo para a LAN. Os bloqueios podem ser editados à mão em
`/etc/bind/db.rpz.gwos` (duas linhas por domínio: `dominio.` e `*.dominio.`),
seguidos de `rndc reload`.

## Com os outros

- **25-dns-interno**: o domínio interno passa a ser encaminhado ao dnsmasq
- **10 + 60**: a RPZ passa a ser gerada do banco por
  `scripts/aplicar_bind9_rpz.sh`
- **40-firewall**: todo DNS da LAN é forçado para cá, impedindo bypass da RPZ

## Verificação

```bash
bash verificar.sh
```

Confere o serviço, o `named-checkconf`, a presença do `response-policy` e
resolve `google.com` por `127.0.0.1`.
