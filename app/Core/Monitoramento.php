<?php
namespace App\Core;

/** Consultas operacionais usam contadores observados pelo sistema e logs brutos do Squid. */
class Monitoramento
{
    public static function janela(string $janela): string
    {
        return match ($janela) {
            '1h'=>'1 HOUR', '7d'=>'7 DAY', '30d'=>'30 DAY',
            'hoje'=>'TIMESTAMPDIFF(SECOND, CURDATE(), NOW()) SECOND',
            'mes'=>"TIMESTAMPDIFF(SECOND, DATE_FORMAT(CURDATE(),'%Y-%m-01'), NOW()) SECOND",
            default=>'24 HOUR'
        };
    }

    public static function ranking(string $janela = '24h', int $limite = 10): array
    {
        $limite = in_array($limite, [10,20,50], true) ? $limite : 10;
        $intervalo = self::janela($janela);
        return Database::fetchAll(
            "SELECT a.ip, COALESCE(NULLIF(e.hostname,''), a.ip) AS equipamento,
                    COUNT(*) AS requisicoes, SUM(a.bytes) AS download_bytes,
                    SUM(a.request_bytes) AS upload_bytes,
                    SUM(CASE WHEN a.status LIKE '%DENIED%' OR a.status LIKE '%BLOCKED%' THEN 1 ELSE 0 END) AS bloqueios,
                    MAX(a.ocorrido_em) AS ultimo_acesso
             FROM acessos_internet a LEFT JOIN equipamentos e ON e.ip=a.ip
             WHERE a.ocorrido_em >= NOW() - INTERVAL {$intervalo}
             GROUP BY a.ip, e.hostname ORDER BY (COALESCE(SUM(a.bytes),0)+COALESCE(SUM(a.request_bytes),0)) DESC LIMIT {$limite}"
        );
    }

    public static function acessos(array $filtros = [], int $limite = 200): array
    {
        $periodo=(string)($filtros['periodo']??'24h'); if(!isset(self::periodosPermitidos()[$periodo]))$periodo='24h';
        $intervalo=self::janela($periodo);
        $cond = ["a.ocorrido_em >= NOW() - INTERVAL {$intervalo}"]; $params=[];
        foreach (['ip'=>'a.ip','protocolo'=>'a.protocolo','interface'=>'a.interface_rede'] as $k=>$col) {
            $v = trim((string)($filtros[$k] ?? ''));
            if ($v !== '') { $cond[]="$col = ?"; $params[]=$v; }
        }
        $grupo = filter_var($filtros['grupo'] ?? null, FILTER_VALIDATE_INT);
        if ($grupo !== false && $grupo !== null && $grupo > 0) {
            $cond[] = 'EXISTS (SELECT 1 FROM ips fi WHERE fi.endereco=a.ip AND fi.ativo=1 AND (fi.expira_em IS NULL OR fi.expira_em>NOW()) AND fi.grupo_id=?)';
            $params[] = $grupo;
        }
        $busca = trim((string)($filtros['busca'] ?? ''));
        if ($busca !== '') { $cond[]='(a.dominio LIKE ? OR a.email LIKE ?)'; $params[]='%'.$busca.'%'; $params[]='%'.$busca.'%'; }
        if (($filtros['decisao'] ?? '') === 'bloqueado') $cond[]="(a.status LIKE '%DENIED%' OR a.status LIKE '%BLOCKED%')";
        if (($filtros['decisao'] ?? '') === 'permitido') $cond[]="(a.status NOT LIKE '%DENIED%' AND a.status NOT LIKE '%BLOCKED%')";
        $limite=max(1,min(500,$limite));
        return Database::fetchAll('SELECT a.ocorrido_em,a.ip,a.email,a.metodo,a.protocolo,a.porta,a.dominio,a.destino_ip,a.status,a.bytes,a.request_bytes,a.interface_rede,e.hostname,e.mac FROM acessos_internet a LEFT JOIN equipamentos e ON e.ip=a.ip WHERE '.implode(' AND ',$cond).' ORDER BY a.ocorrido_em DESC LIMIT '.$limite,$params);
    }

    public static function dispositivos(): array
    {
        $rows=Database::fetchAll(
            "SELECT e.ip,e.mac,e.hostname,e.observacao,e.origem,e.interface_rede,e.lease_expira_em,
                    NULL AS grupo_id,NULL AS grupo_nome,NULL AS grupo_tipo,NULL AS expira_em,
                    u.email,s.expira_em sessao_expira,
                    (SELECT COUNT(*) FROM acessos_internet a WHERE a.ip=e.ip AND a.ocorrido_em>=NOW()-INTERVAL 24 HOUR) requisicoes,
                    (SELECT COALESCE(SUM(a.bytes),0) FROM acessos_internet a WHERE a.ip=e.ip AND a.ocorrido_em>=NOW()-INTERVAL 24 HOUR) download_24h,
                    (SELECT SUM(a.request_bytes) FROM acessos_internet a WHERE a.ip=e.ip AND a.ocorrido_em>=NOW()-INTERVAL 24 HOUR) upload_24h,
                    (SELECT MAX(a.ocorrido_em) FROM acessos_internet a WHERE a.ip=e.ip) ultimo_acesso
             FROM equipamentos e LEFT JOIN sessoes_internet s ON s.ip=e.ip AND s.expira_em>NOW()
             LEFT JOIN usuarios_internet u ON u.id=s.usuario_id
             ORDER BY e.ip"
        );
        $politicas=Database::fetchAll('SELECT i.endereco,i.grupo_id,i.expira_em,g.nome grupo_nome,g.tipo grupo_tipo FROM ips i JOIN ip_grupos g ON g.id=i.grupo_id WHERE i.ativo=1 AND g.ativo=1 AND (i.expira_em IS NULL OR i.expira_em>NOW())');
        foreach($rows as &$e) {
            $match=[]; foreach($politicas as $p) if(self::ipPertence($e['ip'],$p['endereco'])) $match[]=$p;
            usort($match,static function(array $a,array $b): int { return self::prefixo($b['endereco'])<=>self::prefixo($a['endereco']); });
            if($match) {
                $e['grupo_id']=count($match)===1?$match[0]['grupo_id']:null;
                $e['grupo_nome']=implode(' / ',array_column($match,'grupo_nome'));
                $e['grupo_tipo']=implode(' / ',array_column($match,'grupo_tipo'));
                $e['expira_em']=$match[0]['expira_em'];
                $e['grupos_conflitantes']=count($match)>1;
            } else $e['grupos_conflitantes']=false;
        }
        unset($e);
        return $rows;
    }

    /** Resolve as políticas IP mais específicas vigentes para um equipamento. */
    public static function gruposParaIp(string $ip): array
    {
        $politicas=Database::fetchAll('SELECT i.endereco,g.nome FROM ips i JOIN ip_grupos g ON g.id=i.grupo_id WHERE i.ativo=1 AND g.ativo=1 AND (i.expira_em IS NULL OR i.expira_em>NOW())');
        $matches=array_values(array_filter($politicas,static fn(array $p): bool=>self::ipPertence($ip,$p['endereco'])));
        if(!$matches)return [];
        usort($matches,static fn(array $a,array $b): int=>self::prefixo($b['endereco'])<=>self::prefixo($a['endereco']));
        $prefixo=self::prefixo($matches[0]['endereco']);
        return array_values(array_unique(array_map(static fn(array $p): string=>(string)$p['nome'],array_filter($matches,static fn(array $p): bool=>self::prefixo($p['endereco'])===$prefixo))));
    }

    private static function prefixo(string $rede): int { $p=explode('/',$rede,2); return isset($p[1])&&ctype_digit($p[1])?(int)$p[1]:(filter_var($p[0],FILTER_VALIDATE_IP,FILTER_FLAG_IPV6)?128:32); }
    private static function ipPertence(string $ip,string $rede): bool {
        [$base,$prefixo]=array_pad(explode('/',$rede,2),2,null); $a=@inet_pton($ip); $b=@inet_pton($base);
        if($a===false||$b===false||strlen($a)!==strlen($b))return false;
        if($prefixo===null)return hash_equals($a,$b);
        $bits=(int)$prefixo; if($bits<0||$bits>strlen($a)*8)return false;
        $bytes=intdiv($bits,8);$rest=$bits%8;
        if($bytes && substr($a,0,$bytes)!==substr($b,0,$bytes))return false;
        if($rest){$mask=(0xff<<(8-$rest))&0xff;if((ord($a[$bytes])&$mask)!==(ord($b[$bytes])&$mask))return false;}
        return true;
    }

    /** Sockets TCP estabelecidos nos listeners do Squid, observados pelo kernel. */

    private const LOG_SQUID = '/var/log/squid/access.log';

    /**
     * Últimas linhas do access.log lidas direto do arquivo (não depende do importador).
     * @return array<int,array<string,mixed>>
     */
    public static function aoVivo(int $limite = 150): array
    {
        $limite = max(10, min(500, $limite));
        if (!is_readable(self::LOG_SQUID)) return [];
        $fp = @fopen(self::LOG_SQUID, 'r');
        if (!$fp) return [];
        $tam = (int) (fstat($fp)['size'] ?? 0);
        $ler = min($tam, 400 * 1024);
        if ($ler <= 0) { fclose($fp); return []; }
        fseek($fp, $tam - $ler);
        $texto = (string) stream_get_contents($fp);
        fclose($fp);
        $linhas = preg_split('/\r?\n/', $texto) ?: [];
        if ($tam > $ler) array_shift($linhas);           // primeira linha pode estar cortada
        $linhas = array_slice(array_values(array_filter($linhas, 'strlen')), -$limite);
        $saida = [];
        foreach (array_reverse($linhas) as $l) {
            $p = preg_split('/\s+/', trim($l));
            if (count($p) < 9 || !preg_match('/^\d+(\.\d+)?$/', $p[0])) continue;
            $legado = count($p) >= 11 && preg_match('/^[A-Z]{1,16}$/i', $p[6]);
            if ($legado) { [$ts, , $ip, $status, $bytes, , $metodo, $url, $usuario] = $p; }
            else         { [$ts, , $ip, $status, $bytes, $metodo, $url, $usuario] = $p; }
            $dominio = ($metodo === 'CONNECT' || !str_contains($url, '://')) ? preg_replace('/:\d+$/', '', $url) : (parse_url($url, PHP_URL_HOST) ?: $url);
            $saida[] = [
                'hora'    => date('H:i:s', (int) $ts),
                'ip'      => $ip,
                'usuario' => ($usuario !== '-' && str_contains($usuario, '@')) ? strtolower(urldecode($usuario)) : null,
                'metodo'  => $metodo,
                'dominio' => mb_substr((string) $dominio, 0, 120),
                'status'  => $status,
                'bytes'   => (int) $bytes,
                'negado'  => str_contains($status, 'DENIED'),
            ];
        }
        if ($saida) {
            $ips = array_values(array_unique(array_column($saida, 'ip')));
            $marcas = implode(',', array_fill(0, count($ips), '?'));
            $nomes = [];
            try { foreach (Database::fetchAll("SELECT ip,hostname FROM equipamentos WHERE ip IN ({$marcas})", $ips) as $e) $nomes[$e['ip']] = $e['hostname']; } catch (\Throwable) {}
            foreach ($saida as &$r) $r['hostname'] = $nomes[$r['ip']] ?? null;
            unset($r);
        }
        return $saida;
    }

    /**
     * Por que a tela de acessos pode estar vazia: confere, na ordem, o Squid, o log,
     * o importador e o tipo de grupo dos clientes.
     * @return array<int,array{nivel:string,msg:string}>
     */
    public static function diagnosticoColeta(): array
    {
        $d = [];
        $ouvindo = [];
        $ss = is_executable('/usr/bin/ss') ? '/usr/bin/ss' : (is_executable('/bin/ss') ? '/bin/ss' : null);
        if ($ss) {
            $o = (string) @shell_exec(escapeshellarg($ss) . ' -Hltn 2>/dev/null');
            foreach ([3127, 3128, 3129] as $p) if (preg_match('/:' . $p . '\s/', $o)) $ouvindo[] = $p;
        }
        if ($ss && !$ouvindo) $d[] = ['nivel' => 'erro', 'msg' => 'O Squid não está escutando nas portas 3127/3128/3129. Sem ele nenhum acesso passa pelo proxy. Veja: systemctl status squid e /var/log/squid/cache.log.'];
        elseif ($ouvindo) $d[] = ['nivel' => 'ok', 'msg' => 'Squid escutando nas portas ' . implode(', ', $ouvindo) . '.'];

        if (!is_file(self::LOG_SQUID)) {
            $d[] = ['nivel' => 'erro', 'msg' => 'O arquivo ' . self::LOG_SQUID . ' não existe: o Squid ainda não registrou nada.'];
        } elseif (!is_readable(self::LOG_SQUID)) {
            $d[] = ['nivel' => 'erro', 'msg' => 'O painel não consegue ler ' . self::LOG_SQUID . '. O usuário www-data precisa estar no grupo proxy (rode: usermod -aG proxy www-data && systemctl restart php*-fpm).'];
        } else {
            $tam = (int) @filesize(self::LOG_SQUID);
            if ($tam === 0) $d[] = ['nivel' => 'aviso', 'msg' => 'O access.log está vazio: nenhum computador passou pelo proxy ainda. Lembrete: IPs do grupo "Liberado" desviam do proxy e NÃO aparecem aqui; para monitorar sem senha use o grupo "Isento". Confira também se o cliente usa este gateway (IP do gateway e DNS).'];
            else {
                $idade = time() - (int) @filemtime(self::LOG_SQUID);
                $d[] = ['nivel' => $idade > 600 ? 'aviso' : 'ok', 'msg' => 'access.log com dados (última gravação há ' . ($idade < 90 ? $idade . ' s' : intdiv($idade, 60) . ' min') . ').'];
            }
        }
        try {
            $ult = Database::valor('SELECT MAX(ocorrido_em) FROM acessos_internet');
            if (!$ult) $d[] = ['nivel' => 'aviso', 'msg' => 'Nenhum acesso importado para o banco ainda (Histórico, Ranking e Relatórios dependem disso). O importador roda a cada minuto pelo cron; teste: php ' . BASE_PATH . '/scripts/importar_acessos_squid.php'];
            else $d[] = ['nivel' => 'ok', 'msg' => 'Último acesso importado para o banco: ' . $ult . '.'];
        } catch (\Throwable) {
            $d[] = ['nivel' => 'erro', 'msg' => 'Não foi possível consultar o banco de acessos.'];
        }
        return $d;
    }

    public static function conexoesAtivas(): array
    {
        $ss = is_executable('/usr/bin/ss') ? '/usr/bin/ss' : (is_executable('/bin/ss') ? '/bin/ss' : null);
        if ($ss === null || !function_exists('proc_open')) return ['disponivel'=>false,'motivo'=>'A ferramenta ss não está disponível para o serviço web.','conexoes'=>[]];
        $pipes=[]; $proc=@proc_open([$ss,'-Htn','state','established'],[1=>['pipe','w'],2=>['pipe','w']],$pipes);
        if (!is_resource($proc)) return ['disponivel'=>false,'motivo'=>'Não foi possível consultar sockets do kernel.','conexoes'=>[]];
        $saida=stream_get_contents($pipes[1]); $erro=stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]); $rc=proc_close($proc);
        if ($rc!==0 || $saida===false) return ['disponivel'=>false,'motivo'=>'A consulta de sockets falhou.','conexoes'=>[]];
        $observadas=[];
        foreach(preg_split('/\r?\n/',trim($saida)) as $linha) {
            $p=preg_split('/\s+/',trim($linha)); if(count($p)<5) continue;
            if(!preg_match('/:(3127|3128|3129)$/',$p[3],$local)) continue;
            $peer=$p[4];
            if(preg_match('/^\[([0-9a-fA-F:]+)\]:(\d+)$/',$peer,$m)) {$ip=$m[1];$porta=(int)$m[2];}
            elseif(preg_match('/^(.+):(\d+)$/',$peer,$m)) {$ip=$m[1];$porta=(int)$m[2];}
            else continue;
            if(!filter_var($ip,FILTER_VALIDATE_IP)) continue;
            $observadas[]=['ip'=>$ip,'porta_cliente'=>$porta,'porta_proxy'=>(int)$local[1],'estado'=>$p[0]];
        }
        if(!$observadas) return ['disponivel'=>true,'motivo'=>'Nenhum socket TCP estabelecido nos listeners Squid observados.','conexoes'=>[]];
        $ips=array_values(array_unique(array_column($observadas,'ip'))); $marcas=implode(',',array_fill(0,count($ips),'?'));
        $equip=[]; foreach(Database::fetchAll("SELECT e.ip,e.mac,e.hostname,u.email FROM equipamentos e LEFT JOIN sessoes_internet s ON s.ip=e.ip AND s.expira_em>NOW() LEFT JOIN usuarios_internet u ON u.id=s.usuario_id WHERE e.ip IN ({$marcas})",$ips) as $e) $equip[$e['ip']]=$e;
        foreach($observadas as &$c) { $e=$equip[$c['ip']]??[]; $c['hostname']=$e['hostname']??null; $c['mac']=$e['mac']??null; $c['email']=$e['email']??null; } unset($c);
        return ['disponivel'=>true,'motivo'=>'Sockets TCP do kernel nas portas do proxy; não inclui destino remoto ou volume por conexão.','conexoes'=>$observadas];
    }

    public static function historicoRede(string $interface,int $pontos=30): array
    {
        if(!preg_match('/^[a-zA-Z0-9_.:-]{1,32}$/',$interface)) return ['labels'=>[],'rx'=>[],'tx'=>[]];
        $pontos=max(2,min(120,$pontos));
        $rows=Database::fetchAll('SELECT rx_bytes,tx_bytes,coletado_em FROM metricas_rede WHERE interface=? ORDER BY coletado_em DESC LIMIT '.($pontos+1),[$interface]);
        $rows=array_reverse($rows); $labels=[];$rx=[];$tx=[];
        for($i=1;$i<count($rows);$i++) {
            $seg=max(1,strtotime($rows[$i]['coletado_em'])-strtotime($rows[$i-1]['coletado_em']));
            $a=(int)$rows[$i-1]['rx_bytes'];$b=(int)$rows[$i]['rx_bytes'];$c=(int)$rows[$i-1]['tx_bytes'];$d=(int)$rows[$i]['tx_bytes'];
            $labels[]=date('H:i',strtotime($rows[$i]['coletado_em'])); $rx[]=$b >= $a ? round(($b-$a)*8/$seg,1) : null; $tx[]=$d >= $c ? round(($d-$c)*8/$seg,1) : null;
        }
        return ['labels'=>$labels,'rx'=>$rx,'tx'=>$tx];
    }

    public static function periodosPermitidos(): array { return ['1h'=>'Última hora','hoje'=>'Hoje','24h'=>'24 horas','7d'=>'7 dias','mes'=>'Mês atual','30d'=>'30 dias']; }

    /**
     * Série das últimas 24 h em 48 faixas de 30 min (bps = delta*8/segundos).
     * Lacunas > 10 min e contador reiniciado viram "sem dados" (null), nunca zero.
     */
    public static function historico24h(string $interface): array
    {
        $vazio=['labels'=>[],'rx'=>[],'tx'=>[],'ultima'=>null,'amostras'=>0];
        if(!preg_match('/^[a-zA-Z0-9_.:-]{1,32}$/',$interface)) return $vazio;
        $rows=Database::fetchAll('SELECT rx_bytes,tx_bytes,UNIX_TIMESTAMP(coletado_em) t FROM metricas_rede WHERE interface=? AND coletado_em>=NOW()-INTERVAL 24 HOUR ORDER BY coletado_em',[$interface]);
        if(count($rows)<2) return $vazio+[];
        $faixa=1800; $agora=time(); $inicio=$agora-48*$faixa; $soma=[]; 
        for($i=1;$i<count($rows);$i++){
            $dt=(int)$rows[$i]['t']-(int)$rows[$i-1]['t'];
            if($dt<=0||$dt>600) continue;
            $drx=(int)$rows[$i]['rx_bytes']-(int)$rows[$i-1]['rx_bytes']; $dtx=(int)$rows[$i]['tx_bytes']-(int)$rows[$i-1]['tx_bytes'];
            if($drx<0||$dtx<0) continue;
            $k=(int)floor(((int)$rows[$i]['t']-$inicio)/$faixa); if($k<0||$k>47) continue;
            $soma[$k]['rx']=($soma[$k]['rx']??0)+$drx*8; $soma[$k]['tx']=($soma[$k]['tx']??0)+$dtx*8; $soma[$k]['s']=($soma[$k]['s']??0)+$dt;
        }
        $labels=[];$rx=[];$tx=[];
        for($k=0;$k<48;$k++){
            $labels[]=date('H:i',$inicio+$k*$faixa);
            if(isset($soma[$k])&&$soma[$k]['s']>0){ $rx[]=round($soma[$k]['rx']/$soma[$k]['s'],1); $tx[]=round($soma[$k]['tx']/$soma[$k]['s'],1); }
            else { $rx[]=null; $tx[]=null; }
        }
        return ['labels'=>$labels,'rx'=>$rx,'tx'=>$tx,'ultima'=>date('H:i:s',(int)end($rows)['t']),'amostras'=>count($rows)];
    }

    /** Estado operacional de uma interface (somente leitura de /sys). */
    public static function interfaceInfo(string $interface): array
    {
        $r=['nome'=>$interface,'existe'=>false,'estado'=>null,'ip'=>null];
        if(!preg_match('/^[a-zA-Z0-9_.:-]{1,32}$/',$interface)||!is_dir('/sys/class/net/'.$interface)) return $r;
        $r['existe']=true;
        $op=@file_get_contents('/sys/class/net/'.$interface.'/operstate'); $r['estado']=$op!==false?trim($op):null;
        $saida=[];$cod=1; @exec('ip -4 -o addr show dev '.escapeshellarg($interface).' 2>/dev/null',$saida,$cod);
        if($saida && preg_match('/inet\s+([0-9.]+)/',$saida[0],$m)) $r['ip']=$m[1];
        return $r;
    }
}
