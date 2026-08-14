<?php
/**
 * GWOS — Rotas das telas de módulo.
 *
 * A visão geral existe sempre. As telas de cada servidor entram aqui à medida
 * que são construídas, e só aparecem no menu quando 'tela' => true no catálogo
 * de App\Core\Modulos — assim o menu nunca mostra link quebrado.
 */

$router->get('/modulos', 'ModuloController@index');
