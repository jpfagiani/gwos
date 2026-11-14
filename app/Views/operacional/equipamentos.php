<?php $titulo='Equipamentos'; $modulo='equipamentos'; $podeEditarEquipamentos = pode_editar(); ?>
<header class="gw-pagina-cabecalho"><h1>Equipamentos</h1><span class="gw-total-itens"><?= count($equipamentos) ?> no inventário</span></header><div class="card gw-equipamentos-painel">
<?php if($podeEditarEquipamentos):?><div class="gw-equipamentos-barra d-flex flex-wrap gap-2 align-items-center"><span class="small text-muted"><span id="qtdSel">0</span> selecionado(s) — ação em lote com prévia:</span>
<button class="btn btn-sm btn-primary" data-gw-acao="alterar_grupo" data-gw-selecao=".sel-eq"><i class="bi bi-people"></i> Alterar grupo</button>
<button class="btn btn-sm btn-primary" data-gw-acao="liberar_temporario" data-gw-selecao=".sel-eq"><i class="bi bi-clock-history"></i> Liberar temporário</button>
<button class="btn btn-sm btn-danger" data-gw-acao="bloquear" data-gw-selecao=".sel-eq"><i class="bi bi-slash-circle"></i> Bloquear</button></div><?php endif;?><div class="table-responsive" tabindex="0" role="region" aria-label="Inventário de equipamentos"><table class="table table-sm table-hover align-middle mb-0 gw-tabela-equipamentos gw-tabela-cartoes" role="table"><thead class="table-light" role="rowgroup"><tr role="row"><?php if($podeEditarEquipamentos):?><th role="columnheader" style="width:32px"><input type="checkbox" id="selTodos" class="form-check-input" aria-label="Selecionar todos"></th><?php endif;?>
            <th role="columnheader" scope="col">Equipamento</th>
            <th role="columnheader" scope="col">Grupo / política</th>
            <th role="columnheader" scope="col">Sessão</th>
            <th role="columnheader" scope="col">Origem</th>
            <th role="columnheader" scope="col">Tráfego HTTP · 24 h</th>
            <th role="columnheader" scope="col">Último acesso</th>
            <th role="columnheader" scope="col" class="acoes-sticky">Ações</th>
        </tr></thead><tbody role="rowgroup"><?php foreach($equipamentos as $e):?><tr role="row"><?php if($podeEditarEquipamentos):?><td role="cell" data-rotulo="Selecionar"><input type="checkbox" class="form-check-input sel-eq" value="<?=h($e['ip'])?>" aria-label="Selecionar <?=h($e['ip'])?>"></td><?php endif;?>
        <td role="cell" data-rotulo="Equipamento" class="gw-equip-identidade">
            <strong class="font-monospace gw-tabela-sem-quebra"><?= h($e['ip']) ?></strong>
            <?php if (!empty($e['hostname'])): ?><div class="text-muted small"><?= h($e['hostname']) ?></div><?php endif; ?>
            <?php if (!empty($e['mac'])): ?><div class="text-muted small font-monospace gw-tabela-sem-quebra" title="MAC"><?= h($e['mac']) ?></div><?php endif; ?>
        </td><td role="cell" data-rotulo="Grupo"><?=h($e['grupo_nome']??'Sem regra')?><?php if($e['expira_em']):?><div class="small text-warning">Regra expira <?=h($e['expira_em'])?></div><?php endif;?></td><td role="cell" data-rotulo="Sessão"><?=h($e['email']??'—')?></td>
        <td role="cell" data-rotulo="Origem" class="gw-tabela-sem-quebra"><?= h($e['origem']) ?></td>
        <td role="cell" data-rotulo="Tráfego HTTP · 24 h" class="gw-equip-trafego">
            <div><span class="text-muted">Requisições</span><strong><?= number_format((int) $e['requisicoes']) ?></strong></div>
            <div><span class="text-muted">Download</span><span><?= formatar_bytes((int) $e['download_24h']) ?></span></div>
            <div><span class="text-muted">Upload</span><span><?= $e['upload_24h'] === null ? 'sem dados' : formatar_bytes((int) $e['upload_24h']) ?></span></div>
        </td>
        <td role="cell" data-rotulo="Último acesso" class="gw-tabela-sem-quebra gw-tabela-data"><?= h($e['ultimo_acesso'] ?? '—') ?></td>
        <td role="cell" data-rotulo="Ações" class="acoes-sticky"><div class="gw-tabela-acoes"><a class="btn btn-sm btn-outline-primary" href="/equipamentos/ficha?ip=<?=rawurlencode($e['ip'])?>" title="Ficha completa"><i class="bi bi-pc-display-horizontal"></i></a> <?php if($podeEditarEquipamentos):?><button class="btn btn-sm btn-outline-danger" data-gw-acao="bloquear" data-gw-ips="<?=h($e['ip'])?>" title="Bloquear"><i class="bi bi-slash-circle"></i></button> <button class="btn btn-sm btn-outline-success" data-gw-acao="liberar_temporario" data-gw-ips="<?=h($e['ip'])?>" title="Liberar temporariamente"><i class="bi bi-clock-history"></i></button><?php endif;?> <a class="btn btn-sm btn-outline-secondary" href="/internet/logs?ip=<?=rawurlencode($e['ip'])?>" title="Histórico de acesso"><i class="bi bi-clock-history"></i></a><?php if($e['email']):?> <a class="btn btn-sm btn-outline-warning" href="/internet" title="Usuários e sessões"><i class="bi bi-person-x"></i></a><?php endif;?></div></td></tr><?php endforeach;?><?php if(!$equipamentos):?><tr role="row"><td role="cell" colspan="<?= $podeEditarEquipamentos ? 8 : 7 ?>" class="text-center text-muted py-4">Nenhum equipamento observado. O inventário será preenchido quando o Squid, o DHCP ou vizinhos da LAN fornecerem dados.</td></tr><?php endif;?></tbody></table></div></div>
<script>(()=>{const t=document.getElementById('selTodos'),q=document.getElementById('qtdSel');const b=()=>[...document.querySelectorAll('.sel-eq')];const u=()=>{if(q)q.textContent=b().filter(x=>x.checked).length};t?.addEventListener('change',()=>{b().forEach(x=>x.checked=t.checked);u()});document.addEventListener('change',e=>{if(e.target.classList?.contains('sel-eq'))u()});})();</script>
