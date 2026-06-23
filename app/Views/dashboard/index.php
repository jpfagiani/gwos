<?php $titulo = 'Dashboard'; $modulo = 'dashboard'; ?>

<!-- Faixa superior: info do servidor + status dos serviços -->
<div class="card border-0 shadow-sm mb-4">
    <div class="card-body py-2 px-3">
        <div class="d-flex flex-wrap align-items-center gap-3">
            <!-- Info compacta -->
            <div class="d-flex align-items-center gap-1 text-muted small">
                <i class="bi bi-hdd-rack"></i>
                <span class="font-monospace text-info fw-semibold" id="infoIp">—</span>
            </div>
            <div class="vr"></div>
            <div class="d-flex align-items-center gap-1 text-muted small">
                <i class="bi bi-router"></i>
                <span class="font-monospace text-info fw-semibold" id="infoGw">—</span>
            </div>
            <div class="vr"></div>
            <div class="d-flex align-items-center gap-1 text-muted small">
                <i class="bi bi-globe"></i>
                <span class="font-monospace text-info fw-semibold" id="infoDns">—</span>
            </div>
            <div class="vr"></div>
            <div class="d-flex align-items-center gap-1 text-muted small">
                <i class="bi bi-activity"></i>
                <span class="text-success fw-semibold" id="infoConn">—</span>
                <span>conexões hoje</span>
            </div>

            <div class="ms-auto d-flex flex-wrap gap-2">
                <?php
                $nomes = [
                    'squid'    => 'Squid',
                    'named'    => 'BIND9',
                    'nftables' => 'Firewall',
                    'nginx'    => 'Nginx',
                    'mariadb'  => 'MariaDB',
                ];
                foreach ($servicos as $svc => $ativo): ?>
                    <span class="badge rounded-pill bg-<?= $ativo ? 'success' : 'danger' ?> d-flex align-items-center gap-1" style="font-size:.75rem;padding:.4em .75em">
                        <i class="bi bi-circle-fill" style="font-size:.5rem"></i>
                        <?= h($nomes[$svc] ?? $svc) ?>
                    </span>
                <?php endforeach; ?>
            </div>
        </div>
    </div>
</div>

<!-- Contadores resumo -->
<div class="row g-3 mb-4">
    <div class="col-sm-6 col-lg-3">
        <div class="card border-0 shadow-sm">
            <div class="card-body d-flex align-items-center gap-3">
                <div class="bg-primary bg-opacity-10 rounded p-3">
                    <i class="bi bi-people-fill text-primary fs-4"></i>
                </div>
                <div>
                    <div class="text-muted small">Grupos Ativos</div>
                    <div class="fw-bold fs-4"><?= $totalGrupos ?></div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-sm-6 col-lg-3">
        <div class="card border-0 shadow-sm">
            <div class="card-body d-flex align-items-center gap-3">
                <div class="bg-success bg-opacity-10 rounded p-3">
                    <i class="bi bi-pc-display text-success fs-4"></i>
                </div>
                <div>
                    <div class="text-muted small">IPs Gerenciados</div>
                    <div class="fw-bold fs-4"><?= $totalIps ?></div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-sm-6 col-lg-3">
        <div class="card border-0 shadow-sm">
            <div class="card-body d-flex align-items-center gap-3">
                <div class="bg-warning bg-opacity-10 rounded p-3">
                    <i class="bi bi-globe2 text-warning fs-4"></i>
                </div>
                <div>
                    <div class="text-muted small">Domínios</div>
                    <div class="fw-bold fs-4"><?= $totalDominios ?></div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-sm-6 col-lg-3">
        <div class="card border-0 shadow-sm">
            <div class="card-body d-flex align-items-center gap-3">
                <div class="bg-info bg-opacity-10 rounded p-3">
                    <i class="bi bi-arrow-left-right text-info fs-4"></i>
                </div>
                <div>
                    <div class="text-muted small">Regras NAT</div>
                    <div class="fw-bold fs-4"><?= $totalNat ?></div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Gráficos de banda -->
<div class="row g-3 mb-4">
    <div class="col-md-6">
        <div class="card border-0 shadow-sm">
            <div class="card-header bg-white d-flex align-items-center justify-content-between py-2">
                <span class="fw-semibold small"><i class="bi bi-arrow-down-circle text-primary me-1"></i>Rede interna (LAN)</span>
                <small class="text-muted font-monospace" id="lanLabel">aguardando…</small>
            </div>
            <div class="card-body py-2" style="height:80px">
                <canvas id="chartLAN"></canvas>
            </div>
        </div>
    </div>
    <div class="col-md-6">
        <div class="card border-0 shadow-sm">
            <div class="card-header bg-white d-flex align-items-center justify-content-between py-2">
                <span class="fw-semibold small"><i class="bi bi-arrow-up-circle text-success me-1"></i>Rede externa (WAN)</span>
                <small class="text-muted font-monospace" id="wanLabel">aguardando…</small>
            </div>
            <div class="card-body py-2" style="height:80px">
                <canvas id="chartWAN"></canvas>
            </div>
        </div>
    </div>
</div>

<!-- Acessos em tempo real -->
<div class="card border-0 shadow-sm mb-4">
    <div class="card-header bg-white d-flex align-items-center justify-content-between py-2">
        <span class="fw-semibold small"><i class="bi bi-broadcast text-danger me-1"></i>Acessos em tempo real</span>
        <span class="badge bg-success">ao vivo</span>
    </div>
    <div style="max-height:200px;overflow-y:auto">
        <table class="table table-hover table-sm mb-0 small">
            <thead class="table-light sticky-top">
                <tr>
                    <th style="width:115px">Data/Hora</th>
                    <th style="width:130px">IP</th>
                    <th>Destino</th>
                    <th style="width:110px">Grupo</th>
                    <th style="width:90px">Ação</th>
                </tr>
            </thead>
            <tbody id="rtLog">
                <tr><td colspan="5" class="text-center text-muted py-3">Carregando…</td></tr>
            </tbody>

        </table>
    </div>
</div>

<!-- Últimos Acessos -->
<div class="card border-0 shadow-sm">
    <div class="card-header bg-white fw-semibold d-flex align-items-center justify-content-between">
        <span><i class="bi bi-clock-history me-1"></i> Últimos Acessos</span>
        <small class="text-muted fw-normal">25 mais recentes do log do Squid</small>
    </div>
    <div class="table-responsive">
        <table class="table table-hover mb-0 small">
            <thead class="table-light">
                <tr>
                    <th style="width:135px">Data/Hora</th>
                    <th style="width:130px">IP Cliente</th>
                    <th>Domínio</th>
                    <th style="width:110px">Grupo</th>
                    <th style="width:80px" class="text-end">Tráfego</th>
                    <th style="width:90px">Ação</th>
                </tr>
            </thead>
            <tbody>
                <?php if (empty($ultimosAcessos)): ?>
                    <tr><td colspan="6" class="text-center text-muted py-3">Nenhum acesso no log do Squid.</td></tr>
                <?php else: ?>
                    <?php foreach ($ultimosAcessos as $a): ?>
                        <tr>
                            <td class="font-monospace text-muted" style="font-size:.8rem"><?= h($a['data_hora']) ?></td>
                            <td><span class="font-monospace text-primary fw-semibold"><?= h($a['ip_cliente']) ?></span></td>
                            <td class="text-truncate" style="max-width:220px"><?= h($a['dominio']) ?></td>
                            <td><span class="badge bg-secondary"><?= h($a['grupo']) ?></span></td>
                            <td class="text-end font-monospace" style="font-size:.8rem"><?= formatar_bytes((int)$a['bytes']) ?></td>
                            <td>
                                <span class="badge bg-<?= $a['bloqueado'] ? 'danger' : 'success' ?>">
                                    <?= $a['bloqueado'] ? 'NEGADO' : 'PERMITIDO' ?>
                                </span>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                <?php endif; ?>
            </tbody>
        </table>
    </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<script>
(function(){
    const dias = ['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'];
    function tick(){
        const n = new Date(), el = document.getElementById('relogioTopo');
        if(el) el.textContent = n.toTimeString().slice(0,8)+' — '+dias[n.getDay()]+' '+n.toLocaleDateString('pt-BR');
    }
    tick(); setInterval(tick, 1000);

    const pts = 30, lbs = Array(pts).fill('');
    const rxH = Array(pts).fill(0), txH = Array(pts).fill(0);
    const rxW = Array(pts).fill(0), txW = Array(pts).fill(0);
    let rxLast = 0, txLast = 0;

    function mkChart(id, d1, d2, c1, c2){
        return new Chart(document.getElementById(id),{
            type:'line',
            data:{labels:lbs,datasets:[
                {data:d1,borderColor:c1,borderWidth:1.5,pointRadius:0,fill:true,backgroundColor:c1+'33',tension:0.4},
                {data:d2,borderColor:c2,borderWidth:1.5,pointRadius:0,fill:true,backgroundColor:c2+'33',tension:0.4}
            ]},
            options:{responsive:true,maintainAspectRatio:false,animation:false,
                plugins:{legend:{display:false},tooltip:{enabled:false}},
                scales:{x:{display:false},y:{display:false,min:0}}}
        });
    }
    const cL = mkChart('chartLAN', rxH, txH, '#0d6efd', '#198754');
    const cW = mkChart('chartWAN', rxW, txW, '#198754', '#dc3545');

    function fmt(b){ if(b>1e6) return (b/1e6).toFixed(1)+' Mbps'; if(b>1e3) return (b/1e3).toFixed(0)+' Kbps'; return b+' bps'; }

    function atualizar(){
        fetch('/dashboard/info').then(r=>r.json()).then(d=>{
            document.getElementById('infoIp').textContent  = d.ip;
            document.getElementById('infoGw').textContent  = d.gw;
            document.getElementById('infoDns').textContent = d.dns;
            document.getElementById('infoConn').textContent= d.conn;

            if(rxLast){
                const drx = Math.max(0, d.rx - rxLast), dtx = Math.max(0, d.tx - txLast);
                rxH.push(drx); rxH.shift(); txH.push(dtx); txH.shift();
                rxW.push(Math.round(drx*.6)); rxW.shift(); txW.push(Math.round(dtx*.6)); txW.shift();
                cL.options.scales.y.max = Math.max(...rxH,...txH)*1.2||1;
                cW.options.scales.y.max = Math.max(...rxW,...txW)*1.2||1;
                cL.update(); cW.update();
                document.getElementById('lanLabel').textContent = '↓ '+fmt(drx)+' · ↑ '+fmt(dtx);
                document.getElementById('wanLabel').textContent = '↓ '+fmt(Math.round(drx*.6))+' · ↑ '+fmt(Math.round(dtx*.6));
            }
            rxLast = d.rx; txLast = d.tx;

            if(d.log && d.log.length){
                document.getElementById('rtLog').innerHTML = d.log.map(r=>`
                    <tr>
                        <td class="font-monospace">${r.hora}</td>
                        <td class="font-monospace text-primary">${r.ip}</td>
                        <td class="text-truncate" style="max-width:200px">${r.dominio}</td>
                        <td><span class="badge bg-secondary">${r.grupo||'—'}</span></td>
                        <td><span class="badge bg-${r.bloqueado?'danger':'success'}">${r.bloqueado?'NEGADO':'PERMITIDO'}</span></td>
                    </tr>`).join('');
            } else {
                document.getElementById('rtLog').innerHTML = '<tr><td colspan="5" class="text-center text-muted py-3">Sem registros recentes</td></tr>';
            }
        }).catch(()=>{});
    }
    atualizar(); setInterval(atualizar, 5000);
})();
</script>
