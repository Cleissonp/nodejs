<#
.SYNOPSIS
  Instala Node.js LTS (escopo da máquina), configura NPM em C:\NodeJS e instala OpenCode para todos os usuários.
.DESCRIPTION
  - Instala Node.js LTS com winget.
  - Configura os pacotes globais em C:\NodeJS\npm-global e o cache em C:\NodeJS\npm-cache.
  - Inclui C:\NodeJS\npm-global no PATH da máquina.
  - Instala opencode-ai globalmente.
  - Dá permissão de leitura/execução aos usuários comuns, sem permitir que eles alterem os executáveis compartilhados.
  - Se não estiver elevado, solicita elevação via UAC. Ao ser executado por irm | iex, relança o script usando a URL publicada.
#>

$ErrorActionPreference = "Stop"
$InstallUrl = "https://raw.githubusercontent.com/Cleissonp/nodejs/main/install-nodejs.ps1"

# 0. Auto-elevação. Sem #Requires no início, este bloco pode ser executado antes da instalação.
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host "Solicitando permissões de Administrador..." -ForegroundColor Yellow

    if ($PSCommandPath) {
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        # Quando executado por irm | iex, não existe um caminho de arquivo local para relançar.
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$InstallUrl' | iex`""
    }

    Start-Process -FilePath "powershell.exe" -ArgumentList $Arguments -Verb RunAs
    exit
}

Write-Host "=== 1. Instalar Node.js LTS para todos os usuários (escopo da máquina) ===" -ForegroundColor Cyan
try {
    winget install --id OpenJS.NodeJS.LTS --scope machine --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Aviso: winget retornou o código $LASTEXITCODE. Vou verificar se o npm já está instalado." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Aviso no winget: $_. Vou verificar se o npm já está instalado." -ForegroundColor Yellow
}

# Atualiza o PATH desta sessão para reconhecer uma instalação recém-concluída.
$MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$MachinePath;$UserPath"

$NpmCmd = "C:\Program Files\nodejs\npm.cmd"
if (-not (Test-Path -LiteralPath $NpmCmd)) {
    $NpmCommand = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
    if ($NpmCommand) {
        $NpmCmd = $NpmCommand.Source
    } else {
        throw "npm.cmd não foi encontrado. Verifique se o Node.js LTS foi instalado corretamente."
    }
}

Write-Host "`n=== 2. Criar as pastas globais do NPM ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "C:\NodeJS\npm-global" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\NodeJS\npm-cache" | Out-Null

Write-Host "`n=== 3. Permitir leitura/execução para usuários comuns ===" -ForegroundColor Cyan
# Usa SIDs do Windows para evitar diferenças no nome dos grupos entre idiomas.
# Usuários (S-1-5-32-545) recebem somente leitura/execução nos arquivos compartilhados.
icacls "C:\NodeJS" /grant "*S-1-5-32-545:(OI)(CI)RX" /T /C /Q
if ($LASTEXITCODE -ne 0) {
    Write-Host "Aviso: icacls retornou o código $LASTEXITCODE ao aplicar permissões em C:\NodeJS." -ForegroundColor Yellow
}

Write-Host "`n=== 4. Configurar o prefixo e o cache globais do NPM ===" -ForegroundColor Cyan
& $NpmCmd config --global set prefix "C:\NodeJS\npm-global"
if ($LASTEXITCODE -ne 0) { throw "Falha ao configurar o prefix global do NPM." }

& $NpmCmd config --global set cache "C:\NodeJS\npm-cache"
if ($LASTEXITCODE -ne 0) { throw "Falha ao configurar o cache global do NPM." }

# Configuração da instalação para todos os usuários.
$MachineNpmrcDir = "C:\Program Files\nodejs\etc"
$MachineNpmrc = Join-Path $MachineNpmrcDir "npmrc"
New-Item -ItemType Directory -Force -Path $MachineNpmrcDir | Out-Null
$NpmrcContent = "prefix=C:\NodeJS\npm-global`r`ncache=C:\NodeJS\npm-cache`r`n"
Set-Content -LiteralPath $MachineNpmrc -Value $NpmrcContent -Encoding Ascii -Force
Write-Host "npmrc da máquina gravado em: $MachineNpmrc" -ForegroundColor Gray
Get-Content -LiteralPath $MachineNpmrc

Write-Host "`n=== 5. Adicionar o NPM global ao PATH da máquina ===" -ForegroundColor Cyan
$Target = [EnvironmentVariableTarget]::Machine
$OldPath = [Environment]::GetEnvironmentVariable("Path", $Target)
$NpmGlobal = "C:\NodeJS\npm-global"
$PathEntries = @($OldPath -split ";" | Where-Object { $_.TrimEnd("\") -ine $NpmGlobal.TrimEnd("\") })
$NewPath = (@($PathEntries) + $NpmGlobal) -join ";"

if ($NewPath -ne $OldPath) {
    [Environment]::SetEnvironmentVariable("Path", $NewPath, $Target)
    Write-Host "PATH da máquina atualizado." -ForegroundColor Gray
} else {
    Write-Host "PATH da máquina já contém C:\NodeJS\npm-global." -ForegroundColor Gray
}
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "`n=== 6. Instalar OpenCode globalmente ===" -ForegroundColor Cyan
# A instalação é feita elevada; usuários padrão só recebem leitura/execução dos arquivos.
$env:npm_config_prefix = "C:\NodeJS\npm-global"
$env:npm_config_cache = "C:\NodeJS\npm-cache"
& $NpmCmd install -g opencode-ai
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao instalar opencode-ai via NPM (código $LASTEXITCODE)."
}

Write-Host "`n=== 7. Reaplicar leitura/execução no diretório global ===" -ForegroundColor Cyan
icacls "C:\NodeJS\npm-global" /grant "*S-1-5-32-545:(OI)(CI)RX" /T /C /Q
if ($LASTEXITCODE -ne 0) {
    Write-Host "Aviso: icacls retornou o código $LASTEXITCODE em npm-global." -ForegroundColor Yellow
}

Write-Host "`n=== 8. Verificação ===" -ForegroundColor Cyan
Get-ChildItem "C:\NodeJS\npm-global\opencode*" -ErrorAction SilentlyContinue | Format-Table Name -AutoSize
icacls "C:\NodeJS\npm-global" | Select-Object -First 10

$OpenCodeCmd = "C:\NodeJS\npm-global\opencode.cmd"
if (-not (Test-Path -LiteralPath $OpenCodeCmd)) {
    throw "opencode.cmd não foi encontrado em $OpenCodeCmd. Confira a saída da instalação."
}
& $OpenCodeCmd --version
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nOpenCode global OK. Teste também como usuário padrão: opencode --version" -ForegroundColor Green
} else {
    throw "Falha ao executar OpenCode global (código $LASTEXITCODE)."
}

Write-Host "`n=== 9. Verificar instalação antiga no perfil do administrador ===" -ForegroundColor Cyan
$OldOpencode = "$env:APPDATA\npm\opencode.cmd"
if (Test-Path -LiteralPath $OldOpencode) {
    Write-Host "Instalação antiga encontrada em: $OldOpencode" -ForegroundColor Yellow
    Write-Host "Após confirmar a instalação global, você pode remover a antiga separadamente, se desejar." -ForegroundColor Gray
}

Write-Host "`nInstalação e configuração global concluídas com sucesso!" -ForegroundColor Green
Write-Host "Execute este script em cada máquina que precisar configurar." -ForegroundColor Green
