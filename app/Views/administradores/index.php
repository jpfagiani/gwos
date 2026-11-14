<?php $perfis = ['superadmin' => 'Superadministrador', 'admin' => 'Administrador', 'operador' => 'Operador']; ?>

<div class="page-head">
    <div>
        <h4>Administradores do painel</h4>
        <p class="text-muted mb-0">Contas com acesso ao painel administrativo do GWOS.</p>
    </div>
</div>

<div class="row g-3 align-items-start">
    <div class="col-xl-4">
        <section class="card">
            <h2 class="card-header h6 mb-0">Nova conta</h2>
            <form class="card-body" method="post" action="/administradores">
                <?= csrf_field() ?>
                <div class="mb-2">
                    <label class="form-label" for="adminNome">Nome</label>
                    <input class="form-control" id="adminNome" name="nome" maxlength="100" required>
                </div>
                <div class="mb-2">
                    <label class="form-label" for="adminEmail">E-mail de acesso</label>
                    <input class="form-control" id="adminEmail" name="email" type="email" maxlength="150" required>
                </div>
                <div class="mb-2">
                    <label class="form-label" for="adminPerfil">Perfil</label>
                    <select class="form-select" id="adminPerfil" name="perfil">
                        <option value="operador">Operador (somente leitura)</option>
                        <option value="admin">Administrador</option>
                    </select>
                </div>
                <div class="mb-2">
                    <label class="form-label" for="adminSenha">Senha temporária</label>
                    <input class="form-control" id="adminSenha" name="senha" type="password" minlength="12" maxlength="72"
                           autocomplete="new-password" aria-describedby="adminSenhaAjuda" required>
                    <div id="adminSenhaAjuda" class="form-text">Use pelo menos 12 caracteres. A troca é obrigatória no primeiro acesso.</div>
                </div>
                <div class="mb-3">
                    <label class="form-label" for="adminConfirmacao">Confirmar senha</label>
                    <input class="form-control" id="adminConfirmacao" name="confirmacao" type="password"
                           minlength="12" maxlength="72" autocomplete="new-password" required>
                </div>
                <button class="btn btn-primary" type="submit">Criar conta</button>
            </form>
        </section>
    </div>
    <div class="col-xl-8">
        <section class="card">
            <h2 class="card-header h6 mb-0" id="listaAdministradores">Contas cadastradas</h2>
            <div class="table-responsive" role="region" aria-labelledby="listaAdministradores" tabindex="0">
                <table class="table table-sm align-middle mb-0">
                    <thead class="table-light">
                        <tr><th scope="col">Nome</th><th scope="col">E-mail</th><th scope="col">Perfil</th><th scope="col">Estado</th><th scope="col">Último acesso</th></tr>
                    </thead>
                    <tbody>
                        <?php foreach ($administradores as $conta): ?>
                        <tr>
                            <td><?= h($conta['nome']) ?></td>
                            <td><?= h($conta['email']) ?></td>
                            <td><?= h($perfis[$conta['perfil']] ?? $conta['perfil']) ?></td>
                            <td><span class="badge bg-<?= $conta['ativo'] ? 'success' : 'secondary' ?>"><?= $conta['ativo'] ? 'Ativa' : 'Inativa' ?></span></td>
                            <td><?= h($conta['ultimo_login'] ?? '—') ?></td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </section>
    </div>
</div>
