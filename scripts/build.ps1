# Construit la place a partir des sources (source de verite : src/ + default.project.json).
# Sortie : build/GolfChaos.rbxlx (ouvrable directement dans Roblox Studio).
param(
    [string]$Output = 'build/GolfChaos.rbxlx'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$rojo = Join-Path $root 'tools\rojo.exe'
if (-not (Test-Path $rojo)) { & (Join-Path $PSScriptRoot 'install-tools.ps1') }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
& $rojo build default.project.json --output $Output
if ($LASTEXITCODE -ne 0) { throw "rojo build a echoue ($LASTEXITCODE)" }
$item = Get-Item $Output
Write-Host ("Place construite : {0} ({1:N0} octets, {2})" -f $item.FullName, $item.Length, $item.LastWriteTime)
