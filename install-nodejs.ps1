# Instala o Node.js LTS para todos os usuários (requer PowerShell como Administrador).

$ErrorActionPreference = "Stop"

# 1. Instalar o Node.js LTS para todos os usuários do sistema (escopo da máquina).
winget install --id OpenJS.NodeJS.LTS --scope machine --accept-package-agreements --accept-source-agreements

if ($LASTEXITCODE -ne 0) {
    throw "A instalação do Node.js via winget falhou (código $LASTEXITCODE)."
}

# 2. Criar as pastas globais públicas para o NPM.
New-Item -ItemType Directory -Force -Path "C:\NodeJS\npm-global" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\NodeJS\npm-cache" | Out-Null

# 3. Validar o caminho do npm antes de configurar.
$NpmCmd = "C:\Program Files\nodejs\npm.cmd"
if (-not (Test-Path $NpmCmd)) {
    throw "npm.cmd não foi encontrado em '$NpmCmd'. Verifique a instalação do Node.js."
}

# Configurar o prefixo e o cache globais do NPM.
& $NpmCmd config --global set prefix "C:\NodeJS\npm-global"
if ($LASTEXITCODE -ne 0) { throw "Falha ao configurar o prefix global do NPM." }

& $NpmCmd config --global set cache "C:\NodeJS\npm-cache"
if ($LASTEXITCODE -ne 0) { throw "Falha ao configurar o cache global do NPM." }

# 4. Adicionar a pasta do NPM Global ao PATH do sistema, sem duplicá-la.
$Target = [EnvironmentVariableTarget]::Machine
$OldPath = [Environment]::GetEnvironmentVariable("Path", $Target)
$NpmGlobal = "C:\NodeJS\npm-global"

$PathEntries = @($OldPath -split ";" | Where-Object { $_.TrimEnd("\") -ne $NpmGlobal.TrimEnd("\") })
$NewPath = (@($PathEntries) + $NpmGlobal) -join ";"

if ($NewPath -ne $OldPath) {
    [Environment]::SetEnvironmentVariable("Path", $NewPath, $Target)
}

Write-Host "Instalação e configuração global do Node.js concluídas com sucesso!" -ForegroundColor Green
Write-Host "Node.js e NPM podem exigir um novo terminal para atualizar o PATH."
