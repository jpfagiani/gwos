<?php $titulo = 'Dashboard'; $modulo = 'dashboard'; ?>

<div class="row g-3 mb-4">
    <?php
    $nomes = [
        'squid'   => 'Squid (Proxy)',
        'named'   => 'BIND9 (DNS)',
        'nftables'=> 'nftables (Firewall)',
        'nginx'   => 'Nginx (Web)',
        'mariadb' => 'MariaDB',
    ];
    foreach ($servicos as $svc => $ativo): ?>
        <div class="col-md-4 col-lg-2">
            <div class="card border-0 shadow-sm h-100">
                <div class="card-body text-center py-3">
                    <div class="mb-1">
                        <i class="bi bi-circle-fill text-<?= $ativo ? 'success' : 'danger' ?>" style="font-size:1.4rem;"></i>
                    </div>
                    <div class="fw-semibold small"><?= h($nomes[$svc] ?? $svc) ?></div>
                    <span class="badge bg-<?= $ativo ? 'success' : 'danger' ?> mt-1">
                        <?= $ativo ? 'Ativo' : 'Inativo' ?>
                    </span>
                </div>
            </div>
        </div>
    <?php endforeach; ?>
</div>

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

<div class="card border-0 shadow-sm">
    <div class="card-header bg-white fw-semibold">
        <i class="bi bi-clock-history me-1"></i> Últimos Acessos
    </div>
    <div class="table-responsive">
        <table class="table table-hover mb-0 small">
            <thead class="table-light">
                <tr>
                    <th>Data</th>
                    <th>IP Cliente</th>
                    <th>Domínio</th>
                    <th class="text-end">Requisições</th>
                    <th class="text-end">Tráfego</th>
                </tr>
            </thead>
            <tbody>
                <?php if (empty($ultimosAcessos)): ?>
                    <tr><td colspan="5" class="text-center text-muted py-3">Nenhum acesso registrado.</td></tr>
                <?php else: ?>
                    <?php foreach ($ultimosAcessos as $a): ?>
                        <tr>
                            <td><?= h($a['data']) ?></td>
                            <td><span class="font-monospace text-primary fw-semibold"><?= h($a['ip_cliente']) ?></span></td>
                            <td><?= h($a['dominio']) ?></td>
                            <td class="text-end"><?= number_format($a['acessos']) ?></td>
                            <td class="text-end"><?= formatar_bytes((int)$a['bytes']) ?></td>
                        </tr>
                    <?php endforeach; ?>
                <?php endif; ?>
            </tbody>
        </table>
    </div>
</div>
