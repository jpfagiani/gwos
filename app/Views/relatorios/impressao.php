<?php
$volume = static fn ($bytes): string => $bytes === null ? 'Sem medição' : formatar_bytes((int) $bytes);
$numero = static fn ($valor): string => number_format((int) $valor, 0, ',', '.');
$periodo = static fn (string $data): string => date('d/m/Y', strtotime($data));
$parametros = http_build_query(['data_inicio' => $data_inicio, 'data_fim' => $data_fim]);
$tabela = static function (string $titulo, array $colunas, array $linhas, callable $valores, ?int $limite = null): void {
    ?>
    <section>
        <h2><?= h($titulo) ?></h2>
        <?php if (!$linhas): ?>
            <p class="nota">Sem registros no período.</p>
        <?php else: ?>
            <?php if ($limite !== null && count($linhas) === $limite): ?>
                <p class="nota">Limite desta seção atingido (<?= h($limite) ?> linhas). Reduza o período para consultar em partes.</p>
            <?php endif; ?>
            <div class="tabela">
                <table>
                    <thead><tr><?php foreach ($colunas as $coluna): ?><th scope="col"><?= h($coluna) ?></th><?php endforeach; ?></tr></thead>
                    <tbody>
                    <?php foreach ($linhas as $linha): ?>
                        <tr><?php foreach ($valores($linha) as $valor): ?><td><?= h($valor ?? '—') ?></td><?php endforeach; ?></tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
    </section>
    <?php
};
?>
<!doctype html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>GWOS — Relatório de acessos e operações</title>
    <style>
        :root { font: 15px/1.45 system-ui, sans-serif; color: #152238; background: #edf2f7; }
        body { margin: 0; }
        main { max-width: 1100px; margin: 1.5rem auto; padding: clamp(1rem, 4vw, 2rem); background: white; }
        nav { display: flex; flex-wrap: wrap; gap: 1rem; align-items: center; justify-content: space-between; margin-bottom: 1.25rem; }
        a { color: #174f9c; }
        button { font: inherit; color: white; background: #174f9c; border: 0; border-radius: 8px; padding: .6rem 1rem; cursor: pointer; }
        header { border-bottom: 2px solid #174f9c; padding-bottom: .8rem; }
        h1, h2, p { margin: 0 0 .5rem; }
        h1 { font-size: clamp(1.45rem, 3vw, 2rem); }
        h2 { font-size: 1.15rem; }
        section { margin-top: 1.25rem; }
        .nota { color: #44566d; }
        dl { display: grid; grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr)); gap: .65rem; }
        dl div { padding: .65rem; border: 1px solid #cad5e2; border-radius: 8px; }
        dd { margin: 0; font-weight: 700; font-size: 1.1rem; }
        .tabela { overflow-x: auto; }
        table { border-collapse: collapse; width: 100%; font-size: .88rem; }
        th, td { border-bottom: 1px solid #cad5e2; padding: .45rem; text-align: left; vertical-align: top; overflow-wrap: anywhere; }
        th { background: #edf2f7; }
        @page { size: A4 landscape; margin: 12mm; }
        @media print {
            :root { background: white; font-size: 10pt; }
            main { max-width: none; margin: 0; padding: 0; }
            nav { display: none; }
            .tabela { overflow: visible; }
            table { table-layout: fixed; }
            thead { display: table-header-group; }
            tr, dl { break-inside: avoid; }
            h2 { break-after: avoid; }
        }
    </style>
</head>
<body>
<main>
    <nav aria-label="Ações do relatório">
        <a href="/relatorios?<?= h($parametros) ?>">Voltar aos relatórios</a>
        <?php if ($erro === null): ?><button type="button" onclick="window.print()">Imprimir / Salvar em PDF</button><?php endif; ?>
    </nav>
    <header>
        <h1>GWOS — Acessos e operações</h1>
        <?php if ($erro === null): ?>
            <p>Período de <?= h($periodo($data_inicio)) ?> a <?= h($periodo($data_fim)) ?></p>
            <p class="nota">Gerado em <?= h(date('d/m/Y H:i T')) ?></p>
        <?php endif; ?>
    </header>
    <?php if ($erro !== null): ?>
        <p role="alert"><?= h($erro) ?></p>
    <?php else: ?>
        <section aria-labelledby="titulo-resumo">
            <h2 id="titulo-resumo">Resumo do período</h2>
            <dl>
                <div><dt>Requisições</dt><dd><?= h($numero($resumo['requisicoes'])) ?></dd></div>
                <div><dt>Bloqueios</dt><dd><?= h($numero($resumo['bloqueios'])) ?></dd></div>
                <div><dt>Download</dt><dd><?= h($volume($resumo['download'])) ?></dd></div>
                <div><dt>Upload</dt><dd><?= h($volume($resumo['upload'])) ?></dd></div>
            </dl>
            <p class="nota">Dados importados do Squid. Requisições incluem registros permitidos e bloqueados. Tráfego que passa fora do proxy não consta neste relatório.</p>
            <p class="nota">A seção detalhada exibe até <?= h($numero($limiteAcessos)) ?> acessos, dos mais recentes para os mais antigos.</p>
        </section>
        <?php
        $tabela('Acessos detalhados', ['Data e hora', 'IP', 'Usuário', 'Destino', 'Status Squid', 'Download', 'Upload'],
            $acessos, static fn ($a) => [$a['ocorrido_em'], $a['ip'], $a['email'], $a['dominio'], $a['status'],
                $volume($a['bytes']), $volume($a['request_bytes'])], $limiteAcessos);
        $tabela('Tráfego por equipamento', ['Equipamento', 'IP', 'Grupo', 'Interface', 'Requisições', 'Download', 'Upload', 'Bloqueios'],
            $trafego, static fn ($t) => [$t['equipamento'], $t['ip'], $t['grupo'], $t['interface_rede'],
                $numero($t['requisicoes']), $volume($t['download']), $volume($t['upload']), $numero($t['bloqueios'])], 500);
        $tabela('Sessões encerradas', ['Usuário', 'IP', 'Grupo no login', 'Início', 'Fim', 'Motivo'],
            $sessoes, static fn ($s) => [$s['nome_usuario'], $s['ip'], $s['grupo_snapshot'], $s['iniciou_em'], $s['encerrou_em'], $s['motivo']], 1000);
        $tabela('Alertas e eventos', ['Atualizado em', 'Severidade', 'Evento', 'Detalhe', 'Origem', 'Estado', 'Ocorrências'],
            $eventos, static fn ($e) => [$e['criado_em'], $e['severidade'], $e['titulo'], $e['mensagem'], $e['origem'], $e['estado'], $numero($e['ocorrencias'])], 500);
        $tabela('Novos dispositivos observados', ['Atualizado em', 'Evento', 'Detalhe', 'Estado'],
            $novos, static fn ($n) => [$n['criado_em'], $n['titulo'], $n['mensagem'], $n['estado']], 500);
        ?>
    <?php endif; ?>
</main>
</body>
</html>
