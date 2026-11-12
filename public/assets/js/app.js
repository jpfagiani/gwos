/* GWOS — JavaScript global */

const CSRF = document.querySelector('meta[name="csrf-token"]')?.content ?? '';

// Barra lateral no desktop e menu sobreposto em telas estreitas.
const sidebar = document.getElementById('sidebar');
const sidebarToggle = document.getElementById('btnSidebar');
const navBackdrop = document.getElementById('navBackdrop');
if (sidebar && sidebarToggle && navBackdrop) {
    const root = document.documentElement;
    const mobile = window.matchMedia('(max-width: 991.98px)');
    const toggleText = sidebarToggle.querySelector('.menu-toggle-text');
    const storageKey = 'gwos_menu_recolhido';
    let desktopOpen = !root.classList.contains('menu-recolhido');
    let mobileOpen = false;

    function renderMenu() {
        const open = mobile.matches ? mobileOpen : desktopOpen;
        const overlay = mobile.matches && open;
        if (!open && sidebar.contains(document.activeElement)) sidebarToggle.focus();
        root.classList.toggle('menu-recolhido', !desktopOpen);
        sidebar.classList.toggle('aberto', overlay);
        sidebar.inert = !open;
        navBackdrop.classList.toggle('visivel', overlay);
        const label = open ? 'Ocultar menu' : 'Mostrar menu';
        sidebarToggle.setAttribute('aria-expanded', String(open));
        sidebarToggle.setAttribute('aria-label', label);
        if (toggleText) toggleText.textContent = label;
    }

    function setMenuOpen(open) {
        if (mobile.matches) {
            mobileOpen = open;
        } else {
            desktopOpen = open;
            try { localStorage.setItem(storageKey, open ? '0' : '1'); } catch {}
        }
        renderMenu();
    }

    sidebarToggle.addEventListener('click', () => {
        const open = mobile.matches ? mobileOpen : desktopOpen;
        setMenuOpen(!open);
        if (mobile.matches && !open) sidebar.querySelector('nav a, nav button')?.focus();
    });
    navBackdrop.addEventListener('click', () => {
        setMenuOpen(false);
        sidebarToggle.focus();
    });
    sidebar.addEventListener('click', event => {
        if (mobile.matches && event.target.closest('a') && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) {
            setMenuOpen(false);
        }
    });
    document.addEventListener('keydown', event => {
        if (event.defaultPrevented || event.key !== 'Escape') return;
        if (mobileOpen || (!mobile.matches && desktopOpen && sidebar.contains(document.activeElement))) {
            setMenuOpen(false);
            sidebarToggle.focus();
        }
    });
    mobile.addEventListener('change', () => {
        mobileOpen = false;
        renderMenu();
    });
    renderMenu();
}

// API helper
async function api(url, opcoes = {}) {
    const resp = await fetch(url, {
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': CSRF,
            ...opcoes.headers,
        },
        ...opcoes,
    });

    if (resp.status === 401) {
        window.location.href = '/login';
        return null;
    }

    return resp.json();
}

// Atualizar badges de status na topbar
async function atualizarStatus() {
    try {
        const dados = await api('/api/status/servicos');
        if (!dados) return;

        ['nat', 'dns', 'squid'].forEach(srv => {
            const el = document.getElementById('status' + srv.charAt(0).toUpperCase() + srv.slice(1));
            if (!el) return;
            const ok = dados[srv] === true;
            el.className = `badge ${ok ? 'bg-success' : 'bg-danger'}`;
            el.textContent = srv.toUpperCase() + ' ' + (ok ? 'OK' : 'OFF');
        });
    } catch {
        // silencioso — não quebra o painel
    }
}

// Confirmar exclusão
document.addEventListener('click', e => {
    const btn = e.target.closest('[data-confirmar]');
    if (!btn) return;
    const msg = btn.dataset.confirmar || 'Confirma a exclusão?';
    if (!confirm(msg)) e.preventDefault();
});

// Submeter form via fetch (data-ajax)
document.addEventListener('submit', async e => {
    const form = e.target;
    if (!('ajax' in form.dataset)) return;
    e.preventDefault();

    const btn = form.querySelector('[type=submit]');
    const txt = btn?.textContent;
    if (btn) { btn.disabled = true; btn.textContent = 'Aguarde...'; }

    try {
        const body   = new FormData(form);
        const resp   = await fetch(form.action, { method: form.method, body });
        const dados  = await resp.json();

        if (dados.redirecionar) {
            window.location.href = dados.redirecionar;
        } else if (dados.sucesso) {
            mostrarAlerta('success', dados.sucesso);
            if (form.dataset.reload !== undefined) location.reload();
        } else if (dados.erro) {
            mostrarAlerta('danger', dados.erro);
        }
    } catch {
        mostrarAlerta('danger', 'Erro de comunicação com o servidor.');
    } finally {
        if (btn) { btn.disabled = false; btn.textContent = txt; }
    }
});

function mostrarAlerta(tipo, msg) {
    const div = document.createElement('div');
    div.className = `alert alert-${tipo} alert-dismissible fade show position-fixed bottom-0 end-0 m-3`;
    div.style.zIndex = 9999;
    div.innerHTML = msg + '<button type="button" class="btn-close" data-bs-dismiss="alert"></button>';
    document.body.appendChild(div);
    setTimeout(() => div.remove(), 5000);
}

// Tooltips Bootstrap
document.querySelectorAll('[title]').forEach(el => {
    new bootstrap.Tooltip(el, { trigger: 'hover' });
});

// Inicializa
if (document.getElementById('statusNat')) {
    atualizarStatus();
    setInterval(atualizarStatus, 30000);
}
