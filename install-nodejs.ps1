#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Instala Node.js LTS (machine) + NPM global em C:\NodeJS + OpenCode para TODOS os usuarios.
.DESCRIPTION
  Causa do problema "só funciona como administrador":
    - O opencode estava instalado em C:\Users\<Admin>\AppData\Roaming\npm
      Essa pasta tem ACL só para SISTEMA + Administradores + o usuário que instalou.
      Outro usuário Windows não tem nem PATH nem permissão de leitura/execução lá.
  Solução deste script:
    - Instala tudo em C:\NodeJS\npm-global (ACL com BUILTIN\Usuários=RX)
    - Coloca C:\NodeJS\npm-global no PATH da Máquina (vale para todo usuário)
    - Instala opencode-ai com prefix global explícito
    - Corrige ACLs após a instalação
  Uso: clique direito > Executar com PowerShell como Administrador
#>

$ErrorActionPreference = "Stop"

# 0. Auto-elevação (se não estiver como admin, reabre como admin)
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "Reabrindo como Administrador..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "=== 1. Instalar o Node.js LTS para todos os usuários (Escopo da Máquina) ===" -ForegroundColor Cyan
try {
    winget install --id OpenJS.NodeJS.LTS --scope machine --accept-package-agreements --accept-source-agreements
} catch {
    Write-Host "Aviso no winget (pode já estar instalado): $_" -ForegroundColor Yellow
}

# Garante que o node/npm da máquina estejam no PATH desta sessão
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

$NpmCmd = "C:\Program Files\nodejs\npm.cmd"
if (-not (Test-Path -LiteralPath $NpmCmd)) {
    # tenta achar npm no PATH
    $NpmCmd = "npm"
}

Write-Host "`n=== 2. Criar as pastas globais públicas para o NPM ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "C:\NodeJS\npm-global" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\NodeJS\npm-cache" | Out-Null

Write-Host "`n=== 3. Corrigir permissões (todos os usuários precisam ler/executar) ===" -ForegroundColor Cyan
# RX para Usuários, M para Usuários Autenticados — igual ao padrão que já funciona no C:\NodeJS
icacls "C:\NodeJS" /grant "BUILTIN\Usuarios:(OI)(CI)RX" /T /C /Q
icacls "C:\NodeJS" /grant "NT AUTHORITY\Usuarios autenticados:(OI)(CI)M" /T /C /Q

Write-Host "`n=== 4. Configurar o NPM global para apontar para a nova rota ===" -ForegroundColor Cyan
# Isso escreve em %APPDATA%\npm\etc\npmrc do admin atual. Mantido por compatibilidade com seu script original:
& $NpmCmd config --global set prefix "C:\NodeJS\npm-global"
& $NpmCmd config --global set cache "C:\NodeJS\npm-cache"

# Garante para TODOS os usuários futuros: cria npmrc da instalação do Node (lido por todos)
$MachineNpmrcDir = "C:\Program Files\nodejs\etc"
$MachineNpmrc = Join-Path $MachineNpmrcDir "npmrc"
New-Item -ItemType Directory -Force -Path $MachineNpmrcDir | Out-Null
$NpmrcContent = "prefix=C:\NodeJS\npm-global`r`ncache=C:\NodeJS\npm-cache`r`n"
Set-Content -LiteralPath $MachineNpmrc -Value $NpmrcContent -Encoding Ascii -Force
Write-Host "npmrc da máquina gravado em: $MachineNpmrc" -ForegroundColor Gray
Get-Content -LiteralPath $MachineNpmrc

Write-Host "`n=== 5. Adicionar a pasta do NPM Global ao PATH do Sistema ===" -ForegroundColor Cyan
$Target = [EnvironmentVariableTarget]::Machine
$OldPath = [Environment]::GetEnvironmentVariable("Path", $Target)
if ($OldPath -notlike "*C:\NodeJS\npm-global*") {
    $NewPath = "$OldPath;C:\NodeJS\npm-global"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, $Target)
    Write-Host "PATH da máquina atualizado." -ForegroundColor Gray
} else {
    Write-Host "PATH da máquina já continha C:\NodeJS\npm-global." -ForegroundColor Gray
}
# Atualiza PATH da sessão atual
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

Write-Host "`n=== 6. Instalar o OpenCode para TODOS os usuários ===" -ForegroundColor Cyan
# Força o prefix global independente do npmrc do usuário atual
$env:npm_config_prefix = "C:\NodeJS\npm-global"
$env:npm_config_cache = "C:\NodeJS\npm-cache"
& $NpmCmd install -g opencode-ai

Write-Host "`n=== 7. Reaplicar permissões após o install (o npm cria arquivos só p/ o admin) ===" -ForegroundColor Cyan
icacls "C:\NodeJS\npm-global" /grant "BUILTIN\Usuarios:(OI)(CI)RX" /T /C /Q
icacls "C:\NodeJS\npm-global" /grant "NT AUTHORITY\Usuarios autenticados:(OI)(CI)M" /T /C /Q

Write-Host "`n=== 8. Verificação ===" -ForegroundColor Cyan
Get-ChildItem "C:\NodeJS\npm-global\opencode*" | Format-Table Name -AutoSize
icacls "C:\NodeJS\npm-global" | Select-Object -First 10
& "C:\NodeJS\npm-global\opencode.cmd" --version
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nOpenCode global OK. Teste como usuário padrão: logue com outro usuário e rode 'opencode --version'" -ForegroundColor Green
} else {
    Write-Host "`nFalha ao rodar opencode global. Veja os erros acima." -ForegroundColor Red
    exit 1
}

Write-Host "`n=== 9. Limpeza opcional do install antigo (só-admin) ===" -ForegroundColor Cyan
$OldOpencode = "$env:APPDATA\npm\opencode.cmd"
if (Test-Path -LiteralPath $OldOpencode) {
    Write-Host "Encontrado install antigo em: $OldOpencode" -ForegroundColor Yellow
    Write-Host "Ele é invisível para outros usuários. Recomendo remover após confirmar o global:"
    Write-Host '  npm uninstall -g opencode-ai  # com prefix antigo, ou manualmente: Remove-Item "$env:APPDATA\npm\node_modules\opencode-ai" -Recurse -Force' -ForegroundColor Gray
}

Write-Host "`nInstalação e configuração global concluídas com sucesso!" -ForegroundColor Green
Write-Host "Replicar: execute este script como Administrador em cada máquina." -ForegroundColor Green
