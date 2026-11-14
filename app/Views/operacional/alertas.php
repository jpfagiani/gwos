<?php $titulo='Alertas e eventos'; $modulo='alertas'; ?>
<header class="gw-pagina-cabecalho"><h1>Alertas do sistema</h1></header>
<div class="card gw-alertas-painel">
    <div class="gw-alertas-filtros" id="alertasFiltros" hidden>
        <div>
            <label for="alertasEstado" class="form-label">Estado</label>
            <select id="alertasEstado" class="form-select form-select-sm">
                <option value="">Todos</option>
                <option value="aberto">Abertos</option>
                <option value="reconhecido">Reconhecidos</option>
                <option value="resolvido">Resolvidos</option>
            </select>
        </div>
        <div>
            <label for="alertasSeveridade" class="form-label">Severidade</label>
            <select id="alertasSeveridade" class="form-select form-select-sm">
                <option value="">Todas</option>
                <option value="critico">Crítico</option>
                <option value="aviso">Aviso</option>
                <option value="info">Informativo</option>
            </select>
        </div>
        <span id="alertasContagem" class="small text-muted" role="status"></span>
    </div><div class="table-responsive" tabindex="0" role="region" aria-label="Alertas do sistema"><table class="table table-sm table-hover align-middle mb-0 gw-tabela-alertas gw-tabela-cartoes" role="table"><thead class="table-light" role="rowgroup"><tr role="row"><th role="columnheader" scope="col">Severidade</th><th role="columnheader" scope="col">Evento</th><th role="columnheader" scope="col">Origem</th><th role="columnheader" scope="col">Estado</th><th role="columnheader" scope="col">Atualizado</th><th role="columnheader" scope="col">Ações</th></tr></thead><tbody role="rowgroup"><?php foreach($alertas as $a):?><tr role="row" data-estado="<?= h($a['estado']) ?>" data-severidade="<?= h($a['severidade']) ?>"><td role="cell" data-rotulo="Severidade"><span class="badge bg-<?=($a['severidade']==='critico'?'danger':($a['severidade']==='aviso'?'warning':'info'))?>"><?=h($a['severidade'])?></span></td><td role="cell" data-rotulo="Evento" class="gw-alerta-evento"><strong><?=h($a['titulo'])?></strong><div class="small text-muted"><?=h($a['mensagem'])?></div></td>
        <td role="cell" data-rotulo="Origem" class="gw-tabela-sem-quebra"><?= h($a['origem']) ?></td>
        <td role="cell" data-rotulo="Estado"><span class="badge bg-<?= $a['estado'] === 'aberto' ? 'warning' : ($a['estado'] === 'resolvido' ? 'secondary' : 'info') ?>"><?= h(ucfirst($a['estado'])) ?></span></td>
        <td role="cell" data-rotulo="Atualizado" class="gw-tabela-sem-quebra gw-tabela-data"><?= h($a['atualizado_em']) ?></td>
        <td role="cell" data-rotulo="Ações"><div class="gw-tabela-acoes"><?php if($a['estado']==='aberto'):?><form method="post" action="/alertas/<?=h($a['id'])?>/reconhecer"><?=csrf_field()?><button class="btn btn-sm btn-outline-primary">Reconhecer</button></form><?php endif;?><?php if($a['estado']!=='resolvido'):?><form method="post" action="/alertas/<?=h($a['id'])?>/resolver"><?=csrf_field()?><button class="btn btn-sm btn-outline-success">Resolver</button></form><?php endif;?></div></td></tr><?php endforeach;?><?php if(!$alertas):?><tr role="row"><td role="cell" colspan="6" class="text-center text-muted py-4">Sem alertas registrados.</td></tr><?php endif;?><tr role="row" id="alertasSemResultado" hidden><td role="cell" colspan="6" class="text-center text-muted py-4">Nenhum alerta corresponde aos filtros.</td></tr></tbody></table></div></div>

<script>
(() => {
    const filtros = document.getElementById('alertasFiltros');
    const estado = document.getElementById('alertasEstado');
    const severidade = document.getElementById('alertasSeveridade');
    const contagem = document.getElementById('alertasContagem');
    const vazio = document.getElementById('alertasSemResultado');
    const linhas = document.querySelectorAll('.gw-tabela-alertas tr[data-estado]');

    function filtrar() {
        let visiveis = 0;
        for (const linha of linhas) {
            const corresponde = (!estado.value || linha.dataset.estado === estado.value)
                && (!severidade.value || linha.dataset.severidade === severidade.value);
            linha.hidden = !corresponde;
            if (corresponde) visiveis++;
        }
        vazio.hidden = visiveis > 0;
        contagem.textContent = visiveis + ' de ' + linhas.length + ' alertas exibidos';
    }

    if (linhas.length) {
        filtros.hidden = false;
        filtros.addEventListener('change', filtrar);
        filtrar();
    }
})();
</script>
