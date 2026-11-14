<?php
$rotulosTarefa = ['queued' => 'Na fila', 'running' => 'Em execução', 'succeeded' => 'Concluída', 'failed' => 'Falhou', 'timeout' => 'Tempo esgotado', 'unconfirmed' => 'Sem confirmação'];
?>
<div class="d-flex flex-wrap justify-content-between align-items-end gap-2 mb-3">
    <div>
        <h1 class="h4 mb-1">Histórico de operações</h1>
        <p class="text-secondary mb-0">Ações de firewall, DNS, Squid e NAT com resultado verificado.</p>
    </div>
    <small id="atualizadoEm" class="text-secondary" aria-live="polite">Atualizando…</small>
</div>

<div class="alert alert-info" role="status">
    <i class="bi bi-info-circle me-1"></i>
    Operações pendentes são processadas pelo worker agendado. Falhas não são apresentadas como concluídas.
</div>

<div class="card">
    <div class="table-responsive" tabindex="0" role="region" aria-label="Histórico de operações">
        <table class="table table-sm table-hover align-middle mb-0 gw-colunas-compactas gw-tabela-tarefas">
            <thead class="table-light">
                <tr><th>Operação</th><th>Solicitante</th><th>Solicitada</th><th>Estado</th><th>Duração</th><th>Resultado</th></tr>
            </thead>
            <tbody id="listaTarefas">
                <?php if (empty($tarefas)): ?>
                    <tr><td colspan="6" class="text-center text-secondary py-4">Nenhuma operação registrada.</td></tr>
                <?php else: foreach ($tarefas as $t): ?>
                    <tr>
                        <td><span class="fw-semibold"><?= h($t['titulo']) ?></span><br><small class="text-secondary font-monospace"><?= h($t['id']) ?></small></td>
                        <td><?= h($t['solicitante_id'] ?? 'sistema') ?></td>
                        <td><?= h($t['criada_em']) ?></td>
                        <td><span class="badge text-bg-secondary"><?= h($rotulosTarefa[$t['status']] ?? $t['status']) ?></span></td>
                        <td><?= $t['duracao_ms'] === null ? '—' : h(number_format($t['duracao_ms'] / 1000, 1)) . ' s' ?></td>
                        <td><?= h($t['mensagem']) ?></td>
                    </tr>
                <?php endforeach; endif; ?>
            </tbody>
        </table>
    </div>
</div>

<script>
(function(){
    const tbody = document.getElementById('listaTarefas');
    let inFlight = false, timer, delay = 10000;
    const statusLabel = <?= json_encode($rotulosTarefa, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    const statusColor = {queued:'warning',running:'primary',succeeded:'success',failed:'danger',timeout:'danger',unconfirmed:'secondary'};
    function cell(row, text, cls){const td=document.createElement('td');td.textContent=text??'—';if(cls)td.className=cls;row.appendChild(td);return td;}
    async function atualizar(){
        if(inFlight)return; inFlight=true;
        try {
            const resp=await fetch('/tarefas/lista',{headers:{'Accept':'application/json'},cache:'no-store'});
            if(!resp.ok)throw new Error('http');
            const d=await resp.json(); tbody.replaceChildren();
            if(!d.tarefas.length){const tr=document.createElement('tr');const td=cell(tr,'Nenhuma operação registrada.','text-center text-secondary py-4');td.colSpan=6;tbody.appendChild(tr);}
            for(const t of d.tarefas){
                const tr=document.createElement('tr');
                const title=cell(tr,'');const strong=document.createElement('span');strong.className='fw-semibold';strong.textContent=t.titulo;title.appendChild(strong);title.appendChild(document.createElement('br'));const id=document.createElement('small');id.className='text-secondary font-monospace';id.textContent=t.id;title.appendChild(id);
                cell(tr,t.solicitante_id??'sistema');cell(tr,new Date(t.criada_em).toLocaleString('pt-BR'));
                const status=cell(tr,'');const badge=document.createElement('span');badge.className='badge text-bg-'+(statusColor[t.status]||'secondary');badge.textContent=statusLabel[t.status]??t.status;status.appendChild(badge);
                cell(tr,t.duracao_ms===null?'—':(t.duracao_ms/1000).toFixed(1)+' s');cell(tr,t.mensagem);
                tbody.appendChild(tr);
            }
            document.getElementById('atualizadoEm').textContent='Atualizado '+new Date(d.coletado_em).toLocaleTimeString('pt-BR');
            delay=10000;
        } catch(e){document.getElementById('atualizadoEm').textContent='Falha na atualização';delay=Math.min(60000,delay*2);}
        finally{inFlight=false;clearTimeout(timer);timer=setTimeout(atualizar,delay);}
    }
    timer=setTimeout(atualizar,10000);
})();
</script>
