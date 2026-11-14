(() => {
    const field = document.getElementById('dnsForwarders');
    const editor = document.getElementById('dnsEditor');
    const list = document.getElementById('dnsLista');
    const input = document.getElementById('dnsNovoIp');
    const add = document.getElementById('dnsAdicionar');
    const status = document.getElementById('dnsEstadoEditor');
    if (!field || !editor || !list || !input || !add || !status) return;

    const ips = field.value.trim().split(/[\s,]+/).filter(Boolean);
    function render() {
        field.value = ips.join('\n');
        list.replaceChildren();
        for (const [index, ip] of ips.entries()) {
            const item = document.createElement('li');
            const label = document.createElement('span');
            label.className = 'font-monospace';
            label.textContent = ip;
            const remove = document.createElement('button');
            remove.type = 'button';
            remove.className = 'btn btn-sm btn-outline-danger';
            remove.textContent = 'Remover';
            remove.setAttribute('aria-label', 'Remover DNS ' + ip);
            remove.disabled = ips.length === 1;
            remove.addEventListener('click', () => {
                ips.splice(index, 1);
                render();
                input.focus();
                status.textContent = 'Removido da lista. Salve para aplicar.';
            });
            item.append(label, remove);
            list.append(item);
        }
    }

    function addIp() {
        const ip = input.value.trim();
        const ipv4 = /^(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}$/;
        if (!ipv4.test(ip) || ip.split('.').some(octet => Number(octet) > 255)) {
            status.textContent = 'Informe um endereço IPv4 válido.';
            return;
        }
        if (ips.includes(ip)) {
            status.textContent = 'Esse DNS já está na lista.';
            return;
        }
        ips.push(ip);
        input.value = '';
        render();
        input.focus();
        status.textContent = 'Adicionado à lista. Salve para aplicar.';
    }

    add.addEventListener('click', addIp);
    input.addEventListener('keydown', event => {
        if (event.key === 'Enter') {
            event.preventDefault();
            addIp();
        }
    });
    render();
    field.classList.add('d-none');
    field.labels[0]?.classList.add('d-none');
    editor.hidden = false;
})();
