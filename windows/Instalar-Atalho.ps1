param([Parameter(Mandatory=$true)][uri]$Portal)
$ErrorActionPreference = 'Stop'
if ($Portal.Scheme -ne 'https' -or $Portal.AbsolutePath -ne '/acesso' -or
    $Portal.Query -or $Portal.Fragment -or $Portal.UserInfo) {
    throw 'Informe a URL HTTPS do portal terminada em /acesso.'
}
$destino = Join-Path $env:LOCALAPPDATA 'GWOS'
New-Item -ItemType Directory -Path $destino -Force | Out-Null
$agente = Join-Path $destino 'GWOS-Internet.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GWOS-Internet.ps1') -Destination $agente -Force
$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$atalho = $shell.CreateShortcut((Join-Path $desktop 'Entrar na Internet.lnk'))
$atalho.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$atalho.Arguments = '-NoProfile -WindowStyle Hidden -File "' + $agente + '" -Portal "' + $Portal.AbsoluteUri + '"'
$atalho.WorkingDirectory = $destino
$atalho.Description = 'Abre o portal do GWOS e encerra a sessão ao fechar o último navegador monitorado.'
$atalho.Save()
Write-Output 'Atalho Entrar na Internet criado na área de trabalho.'
