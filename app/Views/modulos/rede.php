<div class="page-head">
    <div><h1 class="h4 mb-1">Rede</h1><p class="small text-muted mb-0">Interfaces configuradas e parâmetros do gateway.</p></div>
    <a class="btn btn-outline-primary btn-sm" href="/diagnostico">Ver Diagnóstico</a>
</div>
<div class="row g-2 mb-3">
    <?php foreach ($interfaces as $rotulo => $interface): ?>
    <div class="col-md-6">
        <section class="card">
            <h2 class="card-header h6 mb-0"><?= h($rotulo) ?></h2>
            <div class="card-body">
                <dl class="gw-rede-dados mb-0">
                    <dt>Interface</dt><dd><?= h($interface['nome'] ?: 'Não configurada') ?></dd>
                    <dt>Estado</dt><dd><?= h($interface['estado'] ?? ($interface['nome'] === '' ? 'Sem dados' : ($interface['existe'] ? 'Sem dados' : 'Não encontrada'))) ?></dd>
                    <dt>IPv4 atual</dt><dd class="font-monospace"><?= h($interface['ip'] ?? 'Sem endereço') ?></dd>
                </dl>
            </div>
        </section>
    </div>
    <?php endforeach; ?>
</div>
<section class="card">
    <h2 class="card-header h6 mb-0">Configuração da LAN</h2>
    <div class="card-body">
        <dl class="gw-rede-dados mb-0">
        <?php foreach ($parametros as $rotulo => $valor): ?>
            <dt><?= h($rotulo) ?></dt><dd class="font-monospace"><?= h($valor ?? 'Não configurado') ?></dd>
        <?php endforeach; ?>
        </dl>
    </div>
</section>
