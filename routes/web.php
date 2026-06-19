<?php

$router->get('/login', 'AuthController@formulario');
$router->post('/login', 'AuthController@autenticar');
$router->get('/logout', 'AuthController@sair');

$router->get('/', 'DashboardController@index');

$router->get('/grupos', 'GrupoController@index');
$router->post('/grupos', 'GrupoController@criar');
$router->delete('/grupos/{id}', 'GrupoController@remover');

$router->get('/grupos/{id}/ips', 'GrupoController@ips');
$router->post('/grupos/{id}/ips', 'GrupoController@adicionarIp');
$router->delete('/ips/{id}', 'GrupoController@removerIp');
$router->post('/grupos/aplicar', 'GrupoController@aplicar');

$router->get('/dominios', 'DominioController@index');
$router->post('/dominios', 'DominioController@criar');
$router->delete('/dominios/{id}', 'DominioController@remover');
$router->post('/dominios/aplicar', 'DominioController@aplicar');

$router->get('/horarios', 'HorarioController@index');
$router->post('/horarios', 'HorarioController@criar');
$router->delete('/horarios/{id}', 'HorarioController@remover');

$router->get('/nat', 'NatController@index');
$router->post('/nat', 'NatController@criar');
$router->delete('/nat/{id}', 'NatController@remover');
$router->post('/nat/{id}/toggle', 'NatController@toggle');
$router->post('/nat/aplicar', 'NatController@aplicarTodas');

$router->get('/relatorios', 'RelatorioController@index');

$router->get('/configuracoes', 'ConfigController@index');
$router->post('/configuracoes', 'ConfigController@salvar');

$router->get('/senha/trocar',  'SenhaController@formularioTrocar');
$router->post('/senha/trocar', 'SenhaController@trocar');
$router->get('/senha/reset',   'SenhaController@formularioReset');
$router->post('/senha/reset',  'SenhaController@reset');
$router->get('/senha/gerar',   'SenhaController@formularioGerar');
$router->post('/senha/gerar',  'SenhaController@gerar');
