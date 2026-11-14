# Ouvre la place construite dans une NOUVELLE fenetre Roblox Studio (instance de test separee).
#   -Rebuild   : reconstruit avant ouverture.
#   -CloseOld  : ferme d'abord la fenetre ouverte precedemment par ce script POUR LA MEME INSTANCE
#                (PID memorise dans build/studio-<Instance>.pid) ; aucune autre fenetre n'est touchee.
#   -Instance  : nom logique de la fenetre ("play" par defaut ; "check" = copie dediee aux verifications
#                de compilation en mode Edition, pour ne pas gener les tests en mode Play).
param(
    [switch]$Rebuild,
    [switch]$CloseOld,
    [string]$Instance = 'play',
    [string]$Place = 'build/GolfChaos.rbxlx'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
if ($Rebuild) { & (Join-Path $PSScriptRoot 'build.ps1') -Output $Place }

$pidFile = Join-Path $root ("build\studio-$Instance.pid")
$expectedFile = if ($Instance -eq 'play') { Split-Path -Leaf $Place } else { "GolfChaos_$Instance.rbxlx" }
if ($CloseOld -and (Test-Path $pidFile)) {
    $oldPid = [int](Get-Content $pidFile)
    $old = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    # Securite : on ne ferme QUE la fenetre dont le titre montre exactement la copie de test de cette instance.
    # Une fenetre Studio de l'utilisateur (place cloud ou autre fichier) n'est jamais touchee.
    if ($old -and $old.ProcessName -eq 'RobloxStudioBeta' -and $old.MainWindowTitle -like "*\$expectedFile - Roblox Studio") {
        Stop-Process -Id $oldPid -Force
        Write-Host "Ancienne fenetre '$Instance' fermee (PID $oldPid, $expectedFile)."
        Start-Sleep -Seconds 2
    } elseif ($old) {
        Write-Host "PID $oldPid ne correspond pas a la fenetre '$expectedFile' : rien n'est ferme."
    }
}

# Chaque instance ouvre sa propre copie du fichier (Studio verrouille le fichier ouvert).
$source = (Resolve-Path $Place).Path
$target = if ($Instance -eq 'play') { $source } else {
    $copy = Join-Path (Split-Path -Parent $source) ("GolfChaos_$Instance.rbxlx")
    Copy-Item $source $copy -Force
    $copy
}

$cmd = (Get-ItemProperty 'Registry::HKEY_CLASSES_ROOT\Roblox.Place\shell\open\command').'(default)'
$studio = ($cmd -split '"')[1]
if (-not (Test-Path $studio)) { throw "Roblox Studio introuvable : $studio" }
$proc = Start-Process -FilePath $studio -ArgumentList ('"' + $target + '"') -PassThru
Set-Content -Path $pidFile -Value $proc.Id
Write-Host "Studio '$Instance' lance (PID $($proc.Id)) sur $target"
