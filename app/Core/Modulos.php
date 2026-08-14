<?php

namespace App\Core;

/**
 * GWOS — Registro dos módulos instalados nesta máquina.
 *
 * Lê /etc/gwos/modulos.d/, que os instaladores de modulos/ escrevem. É daqui
 * que o painel descobre o que existe: instalou o chrony, o arquivo aparece e
 * a seção surge no menu na próxima página — sem script de atualização.
 *
 * Nenhuma tela toca o disco direto; tudo passa por aqui. É o que permite,
 * mais adiante, trocar a leitura local por uma chamada remota sem reescrever
 * as telas.
 */
class Modulos
{
    private const DIR_REGISTRO = '/etc/gwos/modulos.d';

    /** Marcador em modulos.d => metadados da seção no painel. */
    private const CATALOGO = [
        'base' => [
            'pasta'    => '00-base',
            'titulo'   => 'Rede',
            'icone'    => 'bi-hdd-network',
            'secao'    => 'Rede',
            'rota'     => '/modulos/rede',
            'servicos' => [],
            'resumo'   => 'Interfaces, IP do gateway e domínio interno',
        ],
        'banco-mariadb' => [
            'pasta'    => '10-banco-mariadb',
            'titulo'   => 'Banco de dados',
            'icone'    => 'bi-database',
            'secao'    => 'Sistema',
            'rota'     => null,          // sem tela própria
            'servicos' => ['mariadb'],
            'resumo'   => 'Grupos, domínios, horários e relatórios',
        ],
        'dns-bind9' => [
            'pasta'    => '20-dns-bind9',
            'titulo'   => 'DNS',
            'icone'    => 'bi-signpost-split',
            'secao'    => 'Rede',
            'rota'     => '/modulos/dns',
            'servicos' => ['named'],
            'resumo'   => 'Resolvers, zonas e bloqueio por domínio',
        ],
        'dns-interno' => [
            'pasta'    => '25-dns-interno-dnsmasq',
            'titulo'   => 'Nomes internos',
            'icone'    => 'bi-tag',
            'secao'    => 'Rede',
            'rota'     => '/modulos/nomes',
            'servicos' => ['gwos-dnsmasq'],
            'resumo'   => 'Vincular um nome a um IP da LAN',
        ],
        'hora-chrony' => [
            'pasta'    => '30-hora-chrony',
            'titulo'   => 'Hora',
            'icone'    => 'bi-clock-history',
            'secao'    => 'Rede',
            'rota'     => '/modulos/hora',
            'servicos' => ['chrony'],
            'resumo'   => 'Servidores NTP e quem sincroniza',
        ],
        'firewall-nftables' => [
            'pasta'    => '40-firewall-nftables',
            'titulo'   => 'Firewall',
            'icone'    => 'bi-shield-lock',
            'secao'    => 'Rede',
            'rota'     => '/modulos/firewall',
            'servicos' => ['nftables'],
            'resumo'   => 'Regras, NAT e redirecionamentos',
        ],
        'proxy-squid' => [
            'pasta'    => '50-proxy-squid',
            'titulo'   => 'Proxy',
            'icone'    => 'bi-globe',
            'secao'    => 'Rede',
            'rota'     => '/modulos/proxy',
            'servicos' => ['squid'],
            'resumo'   => 'Portas, listas e certificado da CA',
        ],
        'painel-web' => [
            'pasta'    => '60-painel-web',
            'titulo'   => 'Painel',
            'icone'    => 'bi-window',
            'secao'    => 'Sistema',
            'rota'     => null,
            'servicos' => ['nginx', 'php8.4-fpm'],
            'resumo'   => 'Este painel',
        ],
    ];

    private static ?array $cache = null;

    /**
     * Módulos instalados, na ordem do catálogo.
     * Cada item traz os metadados mais 'marcador' e 'instalado_em'.
     */
    public static function instalados(): array
    {
        if (self::$cache !== null) {
            return self::$cache;
        }

        $lista = [];
        foreach (self::CATALOGO as $marcador => $meta) {
            $arquivo = self::DIR_REGISTRO . '/' . $marcador;
            if (!is_file($arquivo)) {
                continue;
            }
            $meta['marcador']     = $marcador;
            $meta['instalado_em'] = self::lerCampo($arquivo, 'instalado_em');
            $lista[$marcador]     = $meta;
        }

        return self::$cache = $lista;
    }

    public static function temModulo(string $marcador): bool
    {
        return isset(self::instalados()[$marcador]);
    }

    public static function info(string $marcador): ?array
    {
        return self::instalados()[$marcador] ?? null;
    }

    /**
     * Seções do menu: ['Rede' => [modulo, ...], 'Sistema' => [...]].
     * Só entram módulos instalados que tenham tela.
     */
    public static function menu(): array
    {
        $secoes = [];
        foreach (self::instalados() as $modulo) {
            if ($modulo['rota'] === null) {
                continue;
            }
            $secoes[$modulo['secao']][] = $modulo;
        }
        return $secoes;
    }

    /**
     * Estado dos serviços de um módulo: ['named' => true, ...].
     * Usa systemctl is-active, que não precisa de root.
     */
    public static function statusServicos(string $marcador): array
    {
        $modulo = self::info($marcador);
        if (!$modulo) {
            return [];
        }

        $estado = [];
        foreach ($modulo['servicos'] as $servico) {
            $saida = null;
            $codigo = 1;
            @exec('systemctl is-active ' . escapeshellarg($servico) . ' 2>/dev/null', $saida, $codigo);
            $estado[$servico] = ($codigo === 0);
        }
        return $estado;
    }

    /** O banco é opcional: sem ele o painel roda em modo leve. */
    public static function temBanco(): bool
    {
        return self::temModulo('banco-mariadb') && is_readable('/etc/gwos/db.conf');
    }

    private static function lerCampo(string $arquivo, string $campo): ?string
    {
        foreach (@file($arquivo, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $linha) {
            if (str_starts_with($linha, $campo . '=')) {
                return trim(substr($linha, strlen($campo) + 1));
            }
        }
        return null;
    }
}
