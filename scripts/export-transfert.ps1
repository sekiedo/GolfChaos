# Exporte un paquet de transfert COMPLET du projet Golf Chaos (reprise dans un autre environnement, sans perte).
# Sortie (par défaut build/transfert/, entièrement régénérée à chaque exécution) :
#   00_LISEZMOI_TRANSFERT.md            docs/TRANSFERT.md + annexes générées (arborescence, remotes, priorités, index)
#   NN_<partie>.md                      code source INTÉGRAL, fichier par fichier (chemin Roblox, classe, SHA-256)
#   SHA256SUMS.txt                      empreintes SHA-256 de tous les fichiers exportés
#   GolfChaos_transfert_complet.rbxlx   place construite depuis l'arbre de travail (y compris le travail non commité)
#   GolfChaos_transfert_verifie.rbxlx   place construite depuis le dernier commit
#   golf-chaos.bundle                   dépôt Git complet avec son historique (git clone golf-chaos.bundle)
#   golf-chaos-sources.zip              sources de l'arbre de travail (src, docs, scripts, legacy, fichiers du projet)
# Usage : powershell -NoProfile -ExecutionPolicy Bypass -File scripts/export-transfert.ps1 [-OutDir build/transfert] [-PartMaxKB 230]
param(
    [string]$OutDir = 'build/transfert',
    [int]$PartMaxKB = 230
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$utf8 = New-Object System.Text.UTF8Encoding($false)
$out = Join-Path $root $OutDir
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Read-Text([string]$path) { return [System.IO.File]::ReadAllText((Join-Path $root $path), [System.Text.Encoding]::UTF8) }
function Write-Text([string]$path, [string]$text) { [System.IO.File]::WriteAllText($path, $text.Replace("`r`n", "`n"), $utf8) }   # sorties en LF uniquement
function Get-Sha([string]$path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root $path)).Hash.ToLowerInvariant() }
function Esc([string]$s) { if ($null -eq $s) { return '' }; return $s.Replace('|', '\|').Replace("`r", '').Replace("`n", ' ') }
function Fmt([long]$n) { return $n.ToString('N0', [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')) }

$head = (git rev-parse --short HEAD).Trim()
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$stamp = Get-Date -Format 'dd/MM/yyyy HH:mm'

# Statut Git de chaque fichier modifié ou nouveau (le reste est identique au dernier commit).
$gitStatus = @{}
foreach ($line in (git status --porcelain --untracked-files=all)) {
    if ($line.Length -lt 4) { continue }
    $code = $line.Substring(0, 2)
    $p = $line.Substring(3).Trim().Trim('"')
    if ($p -match ' -> ') { $p = ($p -split ' -> ')[-1] }
    $gitStatus[$p] = $code
}
function Get-Status([string]$rel) {
    if (-not $gitStatus.ContainsKey($rel)) { return 'commité' }
    $code = $gitStatus[$rel]
    if ($code -eq '??') { return 'nouveau, non commité (en cours)' }
    return 'modifié depuis le dernier commit (en cours)'
}

# Correspondance Rojo (default.project.json) : dossier du dépôt -> instance Roblox.
$mounts = @(
    @{ Dir = 'src/shared'; Path = 'ReplicatedStorage.Shared'; Class = 'Folder' },
    @{ Dir = 'src/server'; Path = 'ServerScriptService.Server'; Class = 'Script' },
    @{ Dir = 'src/client'; Path = 'StarterPlayer.StarterPlayerScripts.Client'; Class = 'LocalScript' },
    @{ Dir = 'src/tests'; Path = 'ServerStorage.Tests'; Class = 'Folder' }
)
function Get-RobloxInfo([string]$rel) {
    foreach ($m in $mounts) {
        if ($rel.StartsWith($m.Dir + '/')) {
            $inner = $rel.Substring($m.Dir.Length + 1)
            $parts = $inner.Split('/')
            $file = $parts[$parts.Length - 1]
            $dirs = @()
            if ($parts.Length -gt 1) { $dirs = $parts[0..($parts.Length - 2)] }
            $class = 'ModuleScript'
            $name = $null
            if ($file -eq 'init.server.luau') { $class = 'Script' }
            elseif ($file -eq 'init.client.luau') { $class = 'LocalScript' }
            elseif ($file -eq 'init.luau') { $class = 'ModuleScript' }
            elseif ($file.EndsWith('.server.luau')) { $class = 'Script'; $name = $file.Substring(0, $file.Length - 12) }
            elseif ($file.EndsWith('.client.luau')) { $class = 'LocalScript'; $name = $file.Substring(0, $file.Length - 12) }
            elseif ($file.EndsWith('.luau')) { $name = $file.Substring(0, $file.Length - 5) }
            else { return $null }
            $segments = @($m.Path) + $dirs
            if ($name) { $segments += $name }
            return @{ Path = ($segments -join '.'); Class = $class }
        }
    }
    return $null
}
function Get-Language([string]$rel) {
    switch -Regex ($rel) {
        '\.(luau|lua)$' { return 'lua' }
        '\.json$' { return 'json' }
        '\.ps1$' { return 'powershell' }
        '\.md$' { return 'markdown' }
        default { return 'text' }
    }
}

# ---------------------------------------------------------------------------------------------
# Collecte des fichiers, par zone
# ---------------------------------------------------------------------------------------------
function Get-FilesUnder([string]$dir) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $dir))) { return @() }
    return @(Get-ChildItem -LiteralPath (Join-Path $root $dir) -Recurse -File |
        ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') } |
        Sort-Object)
}
$projectFiles = @('default.project.json', '.gitignore', '.gitattributes', 'README.md') +
    @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File | Sort-Object Name | ForEach-Object { 'scripts/' + $_.Name })
$areas = @(
    @{ Key = 'projet'; Title = 'Projet, configuration Rojo et scripts d''outillage'; Files = @($projectFiles | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) }) },
    @{ Key = 'serveur'; Title = 'Serveur (ServerScriptService.Server)'; Files = (Get-FilesUnder 'src/server') },
    @{ Key = 'partage'; Title = 'Partagé (ReplicatedStorage.Shared)'; Files = (Get-FilesUnder 'src/shared') },
    @{ Key = 'client'; Title = 'Client (StarterPlayer.StarterPlayerScripts.Client)'; Files = (Get-FilesUnder 'src/client') },
    @{ Key = 'tests'; Title = 'Tests (ServerStorage.Tests)'; Files = (Get-FilesUnder 'src/tests') },
    @{ Key = 'docs'; Title = 'Documents du projet (docs/)'; Files = (Get-FilesUnder 'docs') },
    @{ Key = 'prototype'; Title = 'Prototype d''origine (legacy/prototype-etape1, conservé pour référence, non utilisé par le jeu)'; Files = (Get-FilesUnder 'legacy') }
)

$entries = New-Object System.Collections.Generic.List[object]
foreach ($area in $areas) {
    foreach ($rel in $area.Files) {
        $content = Read-Text $rel
        $lineCount = ($content -split "`n").Count
        if ($content.EndsWith("`n")) { $lineCount -= 1 }
        $info = Get-RobloxInfo $rel
        $priority = $null
        $pm = [regex]::Match($content, '(?m)^\s*\w+\.Priority\s*=\s*(-?\d+)')
        if ($pm.Success) { $priority = [int]$pm.Groups[1].Value }
        $entries.Add([pscustomobject]@{
            Area = $area.Key
            AreaTitle = $area.Title
            Rel = $rel
            Content = $content
            Lines = $lineCount
            Bytes = (Get-Item -LiteralPath (Join-Path $root $rel)).Length
            Sha = (Get-Sha $rel)
            RobloxPath = if ($info) { $info.Path } else { $null }
            Class = if ($info) { $info.Class } else { $null }
            Status = (Get-Status $rel)
            Priority = $priority
            Part = ''
        })
    }
}

# ---------------------------------------------------------------------------------------------
# Parties de code source (découpées par zone, <= PartMaxKB chacune sauf fichier plus gros)
# ---------------------------------------------------------------------------------------------
$limit = $PartMaxKB * 1024
$partPlan = New-Object System.Collections.Generic.List[object]
foreach ($area in $areas) {
    $areaEntries = @($entries | Where-Object { $_.Area -eq $area.Key })
    if ($areaEntries.Count -eq 0) { continue }
    $chunks = New-Object System.Collections.Generic.List[object]
    $current = New-Object System.Collections.Generic.List[object]
    $size = 0
    foreach ($e in $areaEntries) {
        if ($current.Count -gt 0 -and ($size + $e.Bytes) -gt $limit) {
            $chunks.Add($current)
            $current = New-Object System.Collections.Generic.List[object]
            $size = 0
        }
        $current.Add($e)
        $size += $e.Bytes
    }
    if ($current.Count -gt 0) { $chunks.Add($current) }
    for ($k = 0; $k -lt $chunks.Count; $k++) {
        $partPlan.Add([pscustomobject]@{ Area = $area; Index = $k + 1; Count = $chunks.Count; Entries = $chunks[$k] })
    }
}
$totalParts = $partPlan.Count
$partNumber = 0
foreach ($plan in $partPlan) {
    $partNumber += 1
    $suffix = if ($plan.Count -gt 1) { '-' + $plan.Index } else { '' }
    $fileName = ('{0:D2}_{1}{2}.md' -f $partNumber, $plan.Area.Key, $suffix)
    $sb = New-Object System.Text.StringBuilder
    $title = $plan.Area.Title
    if ($plan.Count -gt 1) { $title = "$title ($($plan.Index)/$($plan.Count))" }
    [void]$sb.AppendLine("# Golf Chaos — code source intégral, partie $partNumber/$totalParts : $title")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("> Export du $stamp, branche ``$branch``, dernier commit ``$head``. Chaque fichier est reproduit **en entier et sans")
    [void]$sb.AppendLine("> modification** entre les clôtures de code. Empreinte SHA-256 calculée sur le fichier d'origine (UTF-8, fins de ligne LF")
    [void]$sb.AppendLine("> pour .luau/.lua/.md/.json, CRLF pour .ps1). Statut « commité » = identique au dernier commit ; « en cours » = travail")
    [void]$sb.AppendLine("> non commité au moment de l'export (non vérifié). Récapitulatif et liaisons : ``00_LISEZMOI_TRANSFERT.md``.")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Fichiers de cette partie :')
    foreach ($e in $plan.Entries) {
        $label = if ($e.RobloxPath) { "``$($e.RobloxPath)`` ($($e.Class))" } else { "``$($e.Rel)``" }
        [void]$sb.AppendLine("- $label — ``$($e.Rel)``")
    }
    [void]$sb.AppendLine()
    foreach ($e in $plan.Entries) {
        $e.Part = $fileName
        $heading = if ($e.RobloxPath) { $e.RobloxPath } else { $e.Rel }
        [void]$sb.AppendLine("## $heading")
        [void]$sb.AppendLine()
        if ($e.RobloxPath) {
            [void]$sb.AppendLine("- Classe Roblox : **$($e.Class)** — chemin Roblox : ``$($e.RobloxPath)``")
        }
        [void]$sb.AppendLine("- Fichier du dépôt : ``$($e.Rel)``")
        $prio = if ($null -ne $e.Priority) { " · Priority $($e.Priority)" } else { '' }
        [void]$sb.AppendLine("- $(Fmt $e.Lines) lignes · $(Fmt $e.Bytes) octets$prio · SHA-256 ``$($e.Sha)``")
        [void]$sb.AppendLine("- Statut : $($e.Status)")
        [void]$sb.AppendLine()
        $longest = 0
        foreach ($m in [regex]::Matches($e.Content, '`+')) { if ($m.Length -gt $longest) { $longest = $m.Length } }
        $fence = '`' * [Math]::Max(4, $longest + 1)
        [void]$sb.AppendLine($fence + (Get-Language $e.Rel))
        $body = $e.Content.Replace("`r`n", "`n")
        [void]$sb.Append($body)
        if (-not $body.EndsWith("`n")) { [void]$sb.AppendLine() }
        [void]$sb.AppendLine($fence)
        [void]$sb.AppendLine()
    }
    Write-Text (Join-Path $out $fileName) $sb.ToString()
}

# ---------------------------------------------------------------------------------------------
# Places Studio, dépôt Git, archive des sources
# ---------------------------------------------------------------------------------------------
$rojo = Join-Path $root 'tools\rojo.exe'
if (-not (Test-Path -LiteralPath $rojo)) { & (Join-Path $PSScriptRoot 'install-tools.ps1') }
& $rojo build (Join-Path $root 'default.project.json') --output (Join-Path $out 'GolfChaos_transfert_complet.rbxlx')
if ($LASTEXITCODE -ne 0) { throw "rojo build (arbre de travail) a échoué ($LASTEXITCODE)" }

$tmp = Join-Path $root 'build\_transfert_tmp'
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
$headDir = Join-Path $tmp 'head'
New-Item -ItemType Directory -Force -Path $headDir | Out-Null
$tarFile = Join-Path $tmp 'head.tar'
git archive --format=tar -o $tarFile HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive a échoué' }
tar -xf $tarFile -C $headDir
if ($LASTEXITCODE -ne 0) { throw 'extraction tar a échoué' }
& $rojo build (Join-Path $headDir 'default.project.json') --output (Join-Path $out 'GolfChaos_transfert_verifie.rbxlx')
if ($LASTEXITCODE -ne 0) { throw "rojo build (dernier commit) a échoué ($LASTEXITCODE)" }
Remove-Item -LiteralPath $tmp -Recurse -Force

git bundle create (Join-Path $out 'golf-chaos.bundle') --all
if ($LASTEXITCODE -ne 0) { throw 'git bundle a échoué' }

$zipItems = @('src', 'docs', 'scripts', 'legacy', 'default.project.json', 'README.md', '.gitignore', '.gitattributes') |
    ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ }
Compress-Archive -Path $zipItems -DestinationPath (Join-Path $out 'golf-chaos-sources.zip') -Force

$sums = New-Object System.Text.StringBuilder
foreach ($e in $entries) { [void]$sums.AppendLine("$($e.Sha)  $($e.Rel)") }
Write-Text (Join-Path $out 'SHA256SUMS.txt') $sums.ToString()

# ---------------------------------------------------------------------------------------------
# 00_LISEZMOI_TRANSFERT.md : document de passation + annexes générées
# ---------------------------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append((Read-Text 'docs/TRANSFERT.md').Replace("`r`n", "`n"))
[void]$sb.AppendLine()
[void]$sb.AppendLine('---')
[void]$sb.AppendLine()
[void]$sb.AppendLine("> Annexes générées automatiquement le $stamp (branche ``$branch``, dernier commit ``$head``) par ``scripts/export-transfert.ps1``.")
$pending = @($entries | Where-Object { $_.Status -ne 'commité' }).Count
[void]$sb.AppendLine("> $($entries.Count) fichiers exportés, dont $pending non commités au moment de l'export (travail en cours, non vérifié).")
[void]$sb.AppendLine()

# Annexe A : arborescence
[void]$sb.AppendLine('## Annexe A — Arborescence complète (dépôt → Roblox)')
[void]$sb.AppendLine()
[void]$sb.AppendLine('Format : `Nom (Classe)` ; `*` = fichier non commité au moment de l''export (en cours d''écriture, non vérifié).')
[void]$sb.AppendLine()
function Add-Tree([string]$dirRel, [string]$indent, [System.Text.StringBuilder]$target) {
    $full = Join-Path $root $dirRel
    $children = @(Get-ChildItem -LiteralPath $full | Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name)
    foreach ($child in $children) {
        $rel = ($dirRel + '/' + $child.Name)
        if ($child.PSIsContainer) {
            $cls = 'Folder'
            if (Test-Path -LiteralPath (Join-Path $child.FullName 'init.server.luau')) { $cls = 'Script' }
            elseif (Test-Path -LiteralPath (Join-Path $child.FullName 'init.client.luau')) { $cls = 'LocalScript' }
            elseif (Test-Path -LiteralPath (Join-Path $child.FullName 'init.luau')) { $cls = 'ModuleScript' }
            [void]$target.AppendLine("$indent$($child.Name) ($cls)")
            Add-Tree $rel ($indent + '    ') $target
        } elseif ($child.Name -match '\.luau$' -and $child.Name -notmatch '^init(\.server|\.client)?\.luau$') {
            $info = Get-RobloxInfo $rel
            $name = $child.Name -replace '(\.server|\.client)?\.luau$', ''
            $mark = if ((Get-Status $rel) -ne 'commité') { ' *' } else { '' }
            [void]$target.AppendLine("$indent$name ($($info.Class))$mark")
        }
    }
}
foreach ($m in $mounts) {
    $initFile = switch ($m.Class) { 'Script' { 'init.server.luau' } 'LocalScript' { 'init.client.luau' } default { $null } }
    $from = if ($initFile) { " ← $($m.Dir)/$initFile" } else { " ← $($m.Dir)/" }
    [void]$sb.AppendLine("### $($m.Path)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('````text')
    [void]$sb.AppendLine("$($m.Path) ($($m.Class))$from")
    Add-Tree $m.Dir '    ' $sb
    [void]$sb.AppendLine('````')
    [void]$sb.AppendLine()
}

# Annexe B : remotes
[void]$sb.AppendLine('## Annexe B — Remotes (créés à l''exécution dans `ReplicatedStorage.Remotes` par `Shared.Net`)')
[void]$sb.AppendLine()
[void]$sb.AppendLine('Définis dans `src/shared/Net/Remotes/*.luau`. `args` = types vérifiés côté serveur avant le gestionnaire (surplus rejeté) ; `rate`/`burst` = seau à jetons par joueur.')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Remote | Fichier | Type | Sens | Arguments (client → serveur) | Débit | Description |')
[void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- | --- |')
$remoteCount = 0
foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $root 'src/shared/Net/Remotes') -Filter '*.luau' | Sort-Object Name)) {
    $comment = New-Object System.Collections.Generic.List[string]
    foreach ($raw in ((Read-Text ('src/shared/Net/Remotes/' + $file.Name)) -split "`n")) {
        $t = $raw.Trim()
        if ($t.StartsWith('--')) { $comment.Add($t.TrimStart('-').Trim()); continue }
        $rm = [regex]::Match($t, '^\["([^"]+)"\]\s*=\s*\{(.*)\}\s*,?\s*$')
        if ($rm.Success) {
            $name = $rm.Groups[1].Value
            $body = $rm.Groups[2].Value
            $kind = ([regex]::Match($body, 'kind\s*=\s*"(\w+)"')).Groups[1].Value
            $dir = ([regex]::Match($body, 'dir\s*=\s*"(\w+)"')).Groups[1].Value
            $argsMatch = [regex]::Match($body, 'args\s*=\s*\{([^}]*)\}')
            $argsText = if ($argsMatch.Success) { $argsMatch.Groups[1].Value.Trim() } else { '' }
            if ($argsMatch.Success -and $argsText -eq '') { $argsText = '(aucun)' }
            $rate = ([regex]::Match($body, 'rate\s*=\s*([\d.]+)')).Groups[1].Value
            $burst = ([regex]::Match($body, 'burst\s*=\s*([\d.]+)')).Groups[1].Value
            $flow = if ($rate) { "$rate/s" + $(if ($burst) { ", rafale $burst" } else { '' }) } else { '' }
            $desc = ($comment -join ' ')
            [void]$sb.AppendLine("| ``$name`` | $($file.BaseName) | $kind | $dir | $(Esc $argsText) | $flow | $(Esc $desc) |")
            $remoteCount += 1
        }
        $comment.Clear()
    }
}
[void]$sb.AppendLine()
[void]$sb.AppendLine("$remoteCount remotes au total.")
[void]$sb.AppendLine()

# Annexe C : priorités
[void]$sb.AppendLine('## Annexe C — Services et contrôleurs (ordre de démarrage réel, lu dans les fichiers)')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Côté | Module | Priority | Chemin Roblox | Statut |')
[void]$sb.AppendLine('| --- | --- | --- | --- | --- |')
$lifecycle = @($entries | Where-Object { $_.Rel -like 'src/server/Services/*.luau' -or $_.Rel -like 'src/client/Controllers/*.luau' }) |
    Sort-Object @{ Expression = { if ($_.Rel -like 'src/server/*') { 0 } else { 1 } } }, @{ Expression = { if ($null -ne $_.Priority) { $_.Priority } else { 100 } } }, Rel
foreach ($e in $lifecycle) {
    $side = if ($e.Rel -like 'src/server/*') { 'serveur' } else { 'client' }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($e.Rel)
    $prio = if ($null -ne $e.Priority) { "$($e.Priority)" } else { '100 (défaut)' }
    [void]$sb.AppendLine("| $side | $name | $prio | ``$($e.RobloxPath)`` | $($e.Status) |")
}
[void]$sb.AppendLine()

# Annexe D : index des fichiers
[void]$sb.AppendLine('## Annexe D — Index de tous les fichiers exportés')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Fichier du dépôt | Chemin Roblox | Classe | Lignes | Octets | Statut | Partie |')
[void]$sb.AppendLine('| --- | --- | --- | ---: | ---: | --- | --- |')
foreach ($e in $entries) {
    $rp = if ($e.RobloxPath) { "``$($e.RobloxPath)``" } else { '—' }
    $cl = if ($e.Class) { $e.Class } else { '—' }
    [void]$sb.AppendLine("| ``$($e.Rel)`` | $rp | $cl | $(Fmt $e.Lines) | $(Fmt $e.Bytes) | $($e.Status) | ``$($e.Part)`` |")
}
$totalLines = ($entries | Measure-Object -Property Lines -Sum).Sum
$totalBytes = ($entries | Measure-Object -Property Bytes -Sum).Sum
$luau = @($entries | Where-Object { $_.Rel -like 'src/*' -and $_.Rel -like '*.luau' })
$luauLines = ($luau | Measure-Object -Property Lines -Sum).Sum
[void]$sb.AppendLine()
[void]$sb.AppendLine("Total : $($entries.Count) fichiers, $(Fmt $totalLines) lignes, $(Fmt $totalBytes) octets ; dont $($luau.Count) fichiers Luau du jeu ($(Fmt $luauLines) lignes).")
[void]$sb.AppendLine()

# Annexe E : contenu du paquet
[void]$sb.AppendLine('## Annexe E — Contenu du paquet de transfert')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Fichier | Taille | Rôle |')
[void]$sb.AppendLine('| --- | ---: | --- |')
[void]$sb.AppendLine('| `00_LISEZMOI_TRANSFERT.md` | — | ce document (récapitulatif, état, liaisons, annexes) |')
foreach ($f in (Get-ChildItem -LiteralPath $out -File | Sort-Object Name)) {
    $role = switch -Regex ($f.Name) {
        '^\d\d_.*\.md$' { 'code source intégral (voir l''en-tête de la partie)' }
        '_complet\.rbxlx$' { 'place Studio de l''arbre de travail (tout le code, y compris en cours)' }
        '_verifie\.rbxlx$' { 'place Studio du dernier commit' }
        '\.bundle$' { 'dépôt Git complet : git clone golf-chaos.bundle golf-chaos' }
        '\.zip$' { 'archive des sources de l''arbre de travail' }
        'SHA256SUMS' { 'empreintes SHA-256 des fichiers exportés' }
        default { '' }
    }
    [void]$sb.AppendLine("| ``$($f.Name)`` | $(Fmt $f.Length) octets | $role |")
}
Write-Text (Join-Path $out '00_LISEZMOI_TRANSFERT.md') $sb.ToString()

Write-Host ("Paquet de transfert : {0}" -f $out)
Write-Host ("  {0} fichiers exportés ({1} lignes), {2} non commités, {3} parties de code, {4} remotes" -f $entries.Count, $totalLines, $pending, $totalParts, $remoteCount)
Get-ChildItem -LiteralPath $out -File | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-42} {1,12:N0} octets" -f $_.Name, $_.Length) }
