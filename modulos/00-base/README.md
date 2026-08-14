# 00-base — rede e preparação da máquina

Único módulo que reconfigura a rede. Os outros apenas **leem** os parâmetros
que ele grava.

## O que faz

- Pergunta WAN, LAN, rede, IP do gateway, rede secundária e domínio interno
- Máquina física: firmware de placas de rede, microcode da CPU, desativa o
  NetworkManager e fixa o nome das interfaces pelo MAC
  (`/etc/systemd/network/70-gwos-*.link`)
- Gera `/etc/network/interfaces` (com backup do anterior)
- Aplica os IPs com `ip addr` — **não** reinicia o `networking`, para não
  derrubar a sessão SSH
- Liga o encaminhamento de pacotes em `/etc/sysctl.d/90-gwos-base.conf`
- Grava `/etc/gwos/gwos.conf`

## Instalação

```bash
bash instalar.sh
```

É opcional: sem ele, cada módulo detecta a rede sozinho e cria o
`gwos.conf` com os valores encontrados, sem mexer em `/etc/network/interfaces`.
Instale-o quando esta máquina for de fato o gateway.

## Depois

Para trocar o IP use sempre `gwos ip <novo_ip> [rede]` — ele valida, faz
backup e recarrega os serviços. Nunca `systemctl restart networking` num
gateway remoto.

## Verificação

```bash
bash verificar.sh
```

Confere as interfaces, o IP do gateway, o `ip_forward` e a rota padrão.
