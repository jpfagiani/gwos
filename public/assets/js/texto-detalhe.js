(() => {
    const painel = document.getElementById('content');
    if (!painel) return;

    const caixa = document.createElement('div');
    caixa.id = 'gw-texto-completo';
    caixa.className = 'gw-caixa-texto';
    caixa.setAttribute('role', 'tooltip');
    caixa.hidden = true;
    document.body.append(caixa);

    let origem = null;
    let fixado = false;
    let timer;
    const alvo = elemento => elemento instanceof Element ? elemento.closest('.gw-texto-detalhe') : null;
    function fechar() {
        clearTimeout(timer);
        origem?.removeAttribute('aria-describedby');
        origem = null;
        fixado = false;
        caixa.hidden = true;
    }
    function abrir(elemento) {
        if (!elemento || elemento.scrollWidth <= elemento.clientWidth) return;
        clearTimeout(timer);
        if (origem === elemento) return;
        fechar();
        origem = elemento;
        caixa.textContent = elemento.textContent.trim();
        caixa.hidden = false;
        elemento.setAttribute('aria-describedby', caixa.id);
        const r = elemento.getBoundingClientRect();
        const margem = 8;
        const topo = r.bottom + caixa.offsetHeight + margem < window.innerHeight
            ? r.bottom + 4 : Math.max(margem, r.top - caixa.offsetHeight - 4);
        const esquerda = Math.max(margem, Math.min(r.left, window.innerWidth - caixa.offsetWidth - margem));
        caixa.style.top = topo + 'px';
        caixa.style.left = esquerda + 'px';
    }
    function agendarFechamento() {
        clearTimeout(timer);
        if (!fixado) timer = setTimeout(fechar, 140);
    }
    painel.addEventListener('pointerover', event => {
        if (event.pointerType === 'mouse' && !fixado) abrir(alvo(event.target));
    });
    painel.addEventListener('pointerout', event => {
        if (alvo(event.target) === origem && origem && !origem.contains(event.relatedTarget)
            && document.activeElement !== origem) agendarFechamento();
    });
    caixa.addEventListener('pointerenter', () => clearTimeout(timer));
    caixa.addEventListener('pointerleave', () => {
        if (document.activeElement !== origem) agendarFechamento();
    });
    painel.addEventListener('focusin', event => abrir(alvo(event.target)));
    painel.addEventListener('focusout', event => {
        if (alvo(event.target) === origem) fechar();
    });
    function alternar(elemento) {
        if (origem === elemento && fixado) {
            fechar();
            return;
        }
        abrir(elemento);
        fixado = origem === elemento;
    }
    document.addEventListener('click', event => {
        const elemento = alvo(event.target);
        if (elemento && painel.contains(elemento)) alternar(elemento);
        else if (!caixa.contains(event.target)) fechar();
    });
    document.addEventListener('keydown', event => {
        if (event.key === 'Escape') fechar();
        const elemento = alvo(event.target);
        if (elemento && painel.contains(elemento) && ['Enter', ' '].includes(event.key)) {
            event.preventDefault();
            alternar(elemento);
        }
    });
    document.addEventListener('scroll', event => {
        if (event.target !== caixa) fechar();
    }, true);
    window.addEventListener('resize', fechar);
    new MutationObserver(() => {
        if (origem && !origem.isConnected) fechar();
    }).observe(painel, {childList: true, subtree: true});
})();
