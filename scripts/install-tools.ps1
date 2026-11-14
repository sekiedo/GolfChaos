# Installe les outils de construction dans tools/ (aucune modification du systeme ni du PATH).
# Source : release officielle GitHub rojo-rbx/rojo, empreinte SHA-256 verifiee contre celle publiee par GitHub.
param(
    [string]$RojoVersion = '7.7.1'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root 'tools'
New-Item -ItemType Directory -Force -Path $tools | Out-Null

$rojoExe = Join-Path $tools 'rojo.exe'
if (Test-Path $rojoExe) {
    $current = (& $rojoExe --version) -replace 'Rojo ', ''
    if ($current -eq $RojoVersion) { Write-Host "Rojo $RojoVersion deja installe."; exit 0 }
}

$headers = @{ 'User-Agent' = 'golf-chaos-install' }
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/rojo-rbx/rojo/releases/tags/v$RojoVersion" -Headers $headers
$asset = $release.assets | Where-Object { $_.name -eq "rojo-$RojoVersion-windows-x86_64.zip" }
if (-not $asset) { throw "Archive Windows introuvable pour Rojo $RojoVersion" }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("rojo-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $zip = Join-Path $work $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($asset.digest -and $asset.digest -ne "sha256:$hash") { throw "Empreinte SHA-256 inattendue ($hash)" }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $work 'x') -Force
    Copy-Item (Join-Path $work 'x\rojo.exe') $rojoExe -Force
    Write-Host ("Installe : " + (& $rojoExe --version) + "  sha256(zip)=" + $hash)
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
