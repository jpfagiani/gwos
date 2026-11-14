<?php

namespace App\Controllers;

use App\Core\Auth;
use App\Core\Controller;
use App\Core\Estado;
use App\Core\Modulos;
use App\Core\Monitoramento;

/**
 * GWOS — Visão geral dos módulos instalados nesta máquina.
 *
 * Não guarda lista própria: lê /etc/gwos/modulos.d a cada carregamento. Um
 * módulo instalado pelo terminal aparece aqui na próxima página, sem cadastro
 * e sem reiniciar nada.
 */
class ModuloController extends Controller
{
    public function rede(): void
    {
        Auth::exigir();
        if (!Modulos::temModulo('base')) {
            $this->erro404();
            return;
        }
        $wan = Monitoramento::interfaceInfo(Estado::obter('IFACE_WAN', '') ?? '');
        $lan = Monitoramento::interfaceInfo(Estado::obter('IFACE_LAN', '') ?? '');
        $this->view('modulos/rede', [
            'titulo' => 'Rede',
            'modulo' => 'base',
            'interfaces' => ['WAN' => $wan, 'LAN' => $lan],
            'parametros' => [
                'Gateway da LAN' => Estado::obter('IP_GATEWAY'),
                'Rede da LAN' => Estado::obter('REDE_LAN'),
                'Domínio interno' => Estado::obter('DOMINIO_LOCAL'),
            ],
        ]);
    }

    public function index(): void
    {
        Auth::exigir();

        $instalados = Modulos::instalados();

        // Serviços de cada módulo, com o estado atual
        $status = [];
        foreach ($instalados as $marcador => $_) {
            $status[$marcador] = Modulos::statusServicos($marcador);
        }

        $this->view('modulos/index', [
            'titulo'     => 'Módulos',
            'modulo'     => 'modulos',
            'instalados' => $instalados,
            'ausentes'   => Modulos::naoInstalados(),
            'status'     => $status,
            'estado'     => Estado::tudo(),
            'temEstado'  => Estado::existe(),
            'temBanco'   => Modulos::temBanco(),
        ]);
    }
}
