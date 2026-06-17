<?php

namespace App\Controllers;

use App\Core\{Auth, Database, Controller};

class RelatorioController extends Controller
{
    public function index(): void
    {
        Auth::exigir();

        $pagina   = max(1, (int)($_GET['pagina'] ?? 1));
        $por_pag  = 50;
        $offset   = ($pagina - 1) * $por_pag;

        $data_inicio = $_GET['data_inicio'] ?? date('Y-m-01');
        $data_fim    = $_GET['data_fim']    ?? date('Y-m-d');

        $total = (int) Database::valor(
            'SELECT COUNT(*) FROM relatorio_diario WHERE data BETWEEN ? AND ?',
            [$data_inicio, $data_fim]
        );

        $registros = Database::fetchAll(
            'SELECT data, ip_cliente, dominio, total_requisicoes, total_bytes
             FROM relatorio_diario
             WHERE data BETWEEN ? AND ?
             ORDER BY data DESC, total_requisicoes DESC
             LIMIT ? OFFSET ?',
            [$data_inicio, $data_fim, $por_pag, $offset]
        );

        $total_paginas = (int) ceil($total / $por_pag);

        $this->view('relatorios/index', compact(
            'registros', 'pagina', 'total_paginas', 'total', 'data_inicio', 'data_fim'
        ));
    }
}
