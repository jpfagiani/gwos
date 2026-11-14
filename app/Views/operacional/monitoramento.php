<?php $titulo='Monitoramento'; $modulo='monitoramento'; ?>
<div class="page-head"><div><h4 class="mb-1">Tráfego observado</h4><div class="text-muted small">Amostras importadas do access.log do Squid · <?=h($periodos[$f['periodo']??'24h'])?></div><small class="text-muted" id="estadoColeta" role="status">Coleta iniciando</small></div><div class="d-flex gap-2"><button class="btn btn-outline-secondary btn-sm" id="btnPausar" type="button"><i class="bi bi-pause-fill"></i> Pausar</button><button class="btn btn-outline-primary btn-sm" id="btnAtualizar" type="button"><i class="bi bi-arrow-clockwise"></i> Atualizar agora</button></div></div>
<form id="monitorFiltros" class="card card-body mb-3 d-none" method="get"><input type="hidden" name="aba" value="historico"><div class="row g-2 align-items-end gw-filtros"><div class="col-6 col-md-4 col-xl-2"><label class="form-label small mb-1 text-nowrap">Período</label><select name="periodo" class="form-select"><?php foreach($periodos as $k=>$nome):?><option value="<?=h($k)?>" <?=($f['periodo']??'24h')===$k?'selected':''?>><?=h($nome)?></option><?php endforeach;?></select></div><div class="col-6 col-md-4 col-xl-2"><label class="form-label small mb-1 text-nowrap">IP</label><input class="form-control" name="ip" value="<?=h($f['ip']??'')?>" placeholder="192.168.1.20"></div><div class="col-6 col-md-4 col-xl-2"><label class="form-label small mb-1 text-nowrap">Grupo (IP exato)</label><select class="form-select" name="grupo"><option value="">Todos</option><?php foreach($grupos as $g):?><option value="<?=h($g['id'])?>" <?=($f['grupo']??'')==(string)$g['id']?'selected':''?>><?=h($g['nome'])?></option><?php endforeach;?></select></div><div class="col-6 col-md-4 col-xl-2"><label class="form-label small mb-1 text-nowrap">Domínio/usuário</label><input class="form-control" name="busca" value="<?=h($f['busca']??'')?>"></div><div class="col-6 col-md-4 col-xl-2"><label class="form-label small mb-1 text-nowrap">Protocolo</label><select name="protocolo" class="form-select"><option value="">Todos</option><?php foreach(['http','https'] as $p):?><option <?=($f['protocolo']??'')===$p?'selected':''?>><?=$p?></option><?php endforeach;?></select></div><div class="col-6 col-md-4 col-xl-2"><label class="form-label small mb-1 text-nowrap">Decisão</label><select name="decisao" class="form-select"><option value="">Todas</option><option value="permitido" <?=($f['decisao']??'')==='permitido'?'selected':''?>>OK</option><option value="bloqueado" <?=($f['decisao']??'')==='bloqueado'?'selected':''?>>Negado</option></select></div><div class="col-12 col-md-auto"><button class="btn btn-primary w-100 text-nowrap"><i class="bi bi-funnel me-1"></i>Filtrar</button></div></div></form>
<details class="gw-nota-tecnica mb-3"><summary>Fontes dos dados de tráfego</summary><p class="mb-0">Conexões ativas vêm do kernel. Histórico e volume vêm do Squid. Upload representa o tamanho da requisição HTTP informado pelo proxy.</p></details>
<ul class="nav nav-tabs gw-abas-monitor mb-3" aria-label="Visões do monitoramento"><li class="nav-item"><button type="button" class="nav-link active" data-monitor-view="vivo" aria-pressed="true" aria-controls="monitorVivo"><i class="bi bi-broadcast me-1"></i>Ao vivo</button></li><li class="nav-item"><button type="button" class="nav-link" data-monitor-view="conexoes" aria-pressed="false" aria-controls="monitorConexoes">Conexões ativas</button></li><li class="nav-item"><button type="button" class="nav-link" data-monitor-view="historico" aria-pressed="false" aria-controls="monitorHistorico">Histórico de acessos</button></li><li class="nav-item"><button type="button" class="nav-link" data-monitor-view="bloqueios" aria-pressed="false" aria-controls="monitorHistorico">Bloqueios</button></li><li class="nav-item"><a class="nav-link" href="/internet">Sessões de usuários</a></li></ul>
<div id="monitorVivo"><div class="gw-filtro-vivo mb-2"><label for="filtroVivo">Filtrar ao vivo</label><input type="search" id="filtroVivo" class="form-control form-control-sm" placeholder="IP, equipamento, usuário ou destino"></div><div id="vivoDiag" class="mb-2"></div><div class="card"><div class="card-header d-flex justify-content-between"><strong>Últimas requisições no proxy</strong><span class="small text-muted" id="vivoEstado">carregando…</span></div><div class="table-responsive" tabindex="0" role="region" aria-label="Últimas requisições no proxy"><table class="table table-sm table-hover align-middle mb-0 small gw-tabela-monitor-vivo gw-tabela-densa"><colgroup><col class="gw-col-hora"><col class="gw-col-equipamento"><col class="gw-col-usuario"><col class="gw-col-destino"><col class="gw-col-metodo"><col class="gw-col-resultado"><col class="gw-col-bytes"></colgroup><thead class="table-light"><tr><th>Hora</th><th>IP / equipamento</th><th>Usuário</th><th>Destino</th><th>Método</th><th>Resultado</th><th class="text-end">Bytes</th></tr></thead><tbody id="tabelaVivo"><tr><td colspan="7" class="text-center text-muted py-4">Consultando o access.log…</td></tr></tbody></table></div><div class="card-footer small text-muted">Leitura direta do access.log do Squid (independe do importador). Só aparece quem passa pelo proxy: grupos Isento/Parcial e quem fez login; "Liberado" desvia do proxy e "Bloqueado" só vê a whitelist.</div></div></div>
<div id="monitorConexoes" class="d-none"><div class="card"><div class="card-header d-flex justify-content-between"><strong>Sockets estabelecidos no proxy</strong><span class="small text-muted">Consulta direta ao kernel</span></div><div class="table-responsive" tabindex="0" role="region" aria-label="Conexões ativas no proxy"><table class="table table-hover mb-0"><thead class="table-light"><tr><th>Origem</th><th>Porta cliente</th><th>Listener Squid</th><th>Estado</th></tr></thead><tbody id="tabelaConexoes"><tr><td colspan="4" class="text-center text-muted py-4">Consultando sockets ativos…</td></tr></tbody></table></div><div id="estadoConexoes" class="card-footer small text-muted"></div></div></div>
<div id="monitorHistorico" class="d-none">
<div class="card"><div class="table-responsive" tabindex="0" role="region" aria-label="Histórico de tráfego observado"><table class="table table-hover align-middle mb-0 gw-tabela-monitor-historico gw-tabela-densa"><colgroup><col class="gw-col-hora"><col class="gw-col-equipamento"><col class="gw-col-destino"><col class="gw-col-ip-destino"><col class="gw-col-protocolo"><col class="gw-col-interface"><col class="gw-col-resultado"><col class="gw-col-download"><col class="gw-col-upload"></colgroup><thead class="table-light"><tr><th>Horário</th><th>IP / equipamento / usuário</th><th>Destino</th><th>Destino IP</th><th>Protocolo</th><th>Interface</th><th>Decisão</th><th class="text-end">Download</th><th class="text-end">Upload</th></tr></thead><tbody id="tabelaAcessos"><?php if(!$acessos):?><tr><td colspan="9" class="text-center text-muted py-4">Sem registros na janela selecionada. Confira se o Squid está instalado e o importador está ativo.</td></tr><?php endif;?><?php foreach($acessos as $a):$blocked=str_contains($a['status'],'DENIED')||str_contains($a['status'],'BLOCKED');?><tr><td><?=h($a['ocorrido_em'])?></td><td><span class="font-monospace"><?=h($a['ip'])?></span><div class="small"><?=h($a['hostname']??'Sem nome')?></div><div class="small text-muted"><span class="gw-texto-detalhe" tabindex="0"><?=h($a['email']??'sem login')?><?=!empty($a['mac'])?' · '.h($a['mac']):''?></span></div></td><td><span class="gw-texto-detalhe" tabindex="0"><?=h($a['dominio'])?></span><?php if($a['porta']):?><small class="text-muted">:<?=h($a['porta'])?></small><?php endif;?></td><td class="font-monospace"><?=h($a['destino_ip']??'—')?></td><td><?=h(strtoupper($a['protocolo']??'—'))?></td><td><?=h($a['interface_rede']??'—')?></td><td><span class="badge bg-<?=$blocked?'danger':'success'?>"><?=h($a['status'])?></span></td><td class="text-end"><?=formatar_bytes((int)$a['bytes'])?></td><td class="text-end"><?=$a['request_bytes']===null?'sem dados':formatar_bytes((int)$a['request_bytes'])?></td></tr><?php endforeach;?></tbody></table></div></div>
</div>
<script>
(()=>{const body=document.getElementById('tabelaAcessos'),state=document.getElementById('estadoColeta'),pause=document.getElementById('btnPausar'),filters=document.getElementById('monitorFiltros'),connBody=document.getElementById('tabelaConexoes'),connState=document.getElementById('estadoConexoes');let active=true,busy=false;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const bytes=n=>{n=Number(n)||0;if(n<1024)return n+' B';const u=['KB','MB','GB','TB'];let i=-1;do{n/=1024;i++;}while(n>=1024&&i<u.length-1);return n.toFixed(1)+' '+u[i];};
async function refresh(){if(busy)return;busy=true;state.textContent='Consultando dados do Squid e kernel…';try{const p=new URLSearchParams(new FormData(filters));p.set('json','1');if(visao==='bloqueios')p.set('decisao','bloqueado');const res=await fetch('/monitoramento?'+p.toString(),{cache:'no-store',headers:{'Accept':'application/json'}});if(!res.ok)throw Error();const data=await res.json();body.innerHTML=data.acessos.length?data.acessos.map(a=>{const denied=/DENIED|BLOCKED/.test(a.status||'');return `<tr><td>${esc(a.ocorrido_em)}</td><td><span class="font-monospace">${esc(a.ip)}</span><div class="small">${esc(a.hostname||'Sem nome')}</div><div class="small text-muted"><span class="gw-texto-detalhe" tabindex="0">${esc(a.email||'sem login')}${a.mac?' · '+esc(a.mac):''}</span></div></td><td><span class="gw-texto-detalhe" tabindex="0">${esc(a.dominio)}</span>${a.porta?`<small class="text-muted">:${esc(a.porta)}</small>`:''}</td><td class="font-monospace">${esc(a.destino_ip||'—')}</td><td>${esc((a.protocolo||'—').toUpperCase())}</td><td>${esc(a.interface_rede||'—')}</td><td><span class="badge bg-${denied?'danger':'success'}">${esc(a.status)}</span></td><td class="text-end">${bytes(a.bytes)}</td><td class="text-end">${a.request_bytes===null?'sem dados':bytes(a.request_bytes)}</td></tr>`}).join(''):'<tr><td colspan="9" class="text-center text-muted py-4">Sem registros na janela selecionada.</td></tr>';const c=data.conexoes||{disponivel:false,motivo:'Dados de conexão indisponíveis.',conexoes:[]};connBody.innerHTML=c.disponivel&&c.conexoes.length?c.conexoes.map(x=>`<tr><td><span class="font-monospace">${esc(x.ip)}</span><div class="small">${esc(x.hostname||'Sem nome')}</div><div class="small text-muted">${esc(x.email||'sem sessão de usuário')}${x.mac?' · '+esc(x.mac):''}</div></td><td>${esc(x.porta_cliente)}</td><td>${esc(x.porta_proxy)}${x.porta_proxy===3129?' · HTTPS':x.porta_proxy===3128?' · HTTP interceptado':' · proxy explícito'}</td><td><span class="badge bg-success">${esc(x.estado)}</span></td></tr>`).join(''): `<tr><td colspan="4" class="text-center text-muted py-4">${esc(c.motivo)}</td></tr>`;connState.textContent=c.motivo;state.textContent='Atualizado '+new Date(data.coletado_em).toLocaleTimeString('pt-BR')+' · histórico novo após importação cron';}catch{state.textContent='Falha ao consultar; confira a sessão e o estado do banco.';connState.textContent='Falha na consulta de sockets.';}finally{busy=false;}}
const botoes = [...document.querySelectorAll('[data-monitor-view]')];
const abas = {vivo: 'monitorVivo', conexoes: 'monitorConexoes', historico: 'monitorHistorico', bloqueios: 'monitorHistorico'};
let visao = 'vivo';
filters.addEventListener('submit', () => { decisao.disabled = false; });
const decisao = filters.elements.decisao;
let filtroHistorico = decisao.value;
decisao.addEventListener('change', () => { filtroHistorico = decisao.value; });
if (new URLSearchParams(location.search).get('aba') === 'bloqueios') filtroHistorico = '';
function abrirVisao(nova) {
    visao = nova;
    for (const botao of botoes) {
        const selecionado = botao.dataset.monitorView === nova;
        botao.classList.toggle('active', selecionado);
        botao.setAttribute('aria-pressed', String(selecionado));
    }
    for (const id of new Set(Object.values(abas))) document.getElementById(id).classList.toggle('d-none', id !== abas[nova]);
    filters.classList.toggle('d-none', nova !== 'historico' && nova !== 'bloqueios');
    filters.elements.aba.value = nova;
    decisao.value = nova === 'bloqueios' ? 'bloqueado' : filtroHistorico;
    decisao.disabled = nova === 'bloqueios';
    if (nova !== 'vivo' && active) refresh();
    document.dispatchEvent(new CustomEvent('gwos:visao-monitor', {detail: nova}));
}
for (const botao of botoes) botao.addEventListener('click', () => abrirVisao(botao.dataset.monitorView));
const parametros = new URLSearchParams(location.search);
const pedida = parametros.get('aba');
const temFiltro = ['periodo','ip','grupo','busca','protocolo','decisao'].some(nome => parametros.has(nome));
abrirVisao(Object.hasOwn(abas, pedida) ? pedida : temFiltro ? 'historico' : 'vivo');
document.getElementById('btnAtualizar').addEventListener('click', () => {
    if (visao !== 'vivo') refresh();
});
pause.addEventListener('click', () => {
    active = !active;
    pause.innerHTML = active ? '<i class="bi bi-pause-fill"></i> Pausar' : '<i class="bi bi-play-fill"></i> Retomar';
    pause.setAttribute('aria-pressed', String(!active));
    state.textContent = active ? 'Atualização retomada' : 'Atualização pausada';
    if (active && visao !== 'vivo') refresh();
});
setInterval(() => { if (active && visao !== 'vivo' && !document.hidden) refresh(); },15000);
})();
</script>

<script>
(()=>{const painel=document.getElementById('monitorVivo'),corpo=document.getElementById('tabelaVivo'),est=document.getElementById('vivoEstado'),diag=document.getElementById('vivoDiag');
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const bytes=n=>{n=Number(n)||0;if(n<1024)return n+' B';const u=['KB','MB','GB'];let i=-1;do{n/=1024;i++;}while(n>=1024&&i<u.length-1);return n.toFixed(1)+' '+u[i];};
let ativo=true,ocupado=false;
const filtro = document.getElementById('filtroVivo');
function filtrarLinhas() {
    const termos = filtro.value.trim().toLocaleLowerCase('pt-BR').split(/\s+/).filter(Boolean);
    for (const linha of corpo.rows) {
        if (linha.cells.length === 1) continue;
        const texto = linha.textContent.toLocaleLowerCase('pt-BR');
        linha.hidden = !termos.every(termo => texto.includes(termo));
    }
}
filtro.addEventListener('input', filtrarLinhas);
async function vivo(){if(ocupado||painel.classList.contains('d-none'))return;ocupado=true;try{const r=await fetch('/monitoramento?vivo=1',{cache:'no-store',headers:{'Accept':'application/json'}});if(!r.ok)throw Error();const d=await r.json();
corpo.innerHTML=d.ao_vivo.length?d.ao_vivo.map(a=>`<tr class="${a.negado?'gw-requisicao-negada':''}"><td class="text-nowrap">${esc(a.hora)}</td><td><span class="font-monospace">${esc(a.ip)}</span>${a.hostname?`<div class="text-muted">${esc(a.hostname)}</div>`:''}</td><td><span class="gw-texto-detalhe" tabindex="0">${esc(a.usuario||'—')}</span></td><td>${esc(a.dominio)}</td><td>${esc(a.metodo)}</td><td><span class="badge bg-${a.negado?'danger':'success'}">${esc(a.status)}</span></td><td class="text-end">${bytes(a.bytes)}</td></tr>`).join(''):'<tr><td colspan="7" class="text-center text-muted py-4">Nenhuma requisição registrada ainda. Veja o diagnóstico acima.</td></tr>';
filtrarLinhas();
const cor={ok:'success',aviso:'warning',erro:'danger'};const ic={ok:'check-circle',aviso:'exclamation-triangle',erro:'x-octagon'};
const mostrar=d.diagnostico.filter(x=>x.nivel!=='ok'||!d.ao_vivo.length);
diag.innerHTML=mostrar.map(x=>`<div class="alert alert-${cor[x.nivel]} py-2 small mb-2"><i class="bi bi-${ic[x.nivel]} me-1"></i>${esc(x.msg)}</div>`).join('');
est.textContent='Atualizado '+new Date(d.coletado_em).toLocaleTimeString('pt-BR')+' · '+d.ao_vivo.length+' linhas';}catch{est.textContent='Falha ao consultar (sessão expirada?).';}finally{ocupado=false;}}
document.addEventListener('gwos:visao-monitor', event => { if (ativo && event.detail === 'vivo') vivo(); });
document.getElementById('btnAtualizar').addEventListener('click', vivo);
document.getElementById('btnPausar').addEventListener('click', () => {
    ativo = document.getElementById('btnPausar').getAttribute('aria-pressed') !== 'true';
    if (ativo) vivo();
});
vivo();setInterval(()=>{if(ativo&&!document.hidden)vivo();},4000);
})();
</script>
