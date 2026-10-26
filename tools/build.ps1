# Baut index.html aus template.html und data/*.json (ersetzt das fruehere build.mjs, kein Node.js noetig)
# Aufruf: powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1
$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot -Parent
$Utf8 = New-Object Text.UTF8Encoding($false)
function Read-Text([string]$Name) { [IO.File]::ReadAllText((Join-Path $Repo $Name), $Utf8) }

$entries = @()
# ConvertFrom-Json liefert in PowerShell 5.1 ein JSON-Array als ein Objekt; deshalb einzeln anhaengen
foreach ($f in 'gearsets', 'brandsets', 'exotics', 'namedweapons') { foreach ($e in (ConvertFrom-Json (Read-Text "data\$f.json"))) { $entries += $e } }

$ids = @{}
foreach ($e in $entries) {
    $key = "$($e.kind):$($e.id)"
    if ($ids.ContainsKey($key)) { throw "Doppelte ID $key" }
    $ids[$key] = $true
}

# Icons der alten Seite (Schluessel wie hunter-s-fury) auf die neuen IDs (hunters-fury) abbilden
$iconsOld = Read-Text 'data\icons.json' | ConvertFrom-Json
$icons = [ordered]@{}
foreach ($p in $iconsOld.PSObject.Properties) {
    $plain = $p.Name -replace '-', ''
    $match = $entries | Where-Object { ($_.id -replace '-', '') -eq $plain } | Select-Object -First 1
    if ($match) { $icons[[string]$match.id] = [string]$p.Value }
}

# </script> darf im eingebetteten JSON nicht vorkommen
function Inline([string]$Json) { return $Json.Replace('<', ([char]92 + 'u003c')) }
$data = Inline ((Read-Text 'data\gearsets.json').TrimEnd(']') + ',' + (Read-Text 'data\brandsets.json').Trim().TrimStart('[').TrimEnd(']') + ',' + (Read-Text 'data\exotics.json').Trim().TrimStart('[').TrimEnd(']') + ',' + (Read-Text 'data\namedweapons.json').Trim().TrimStart('['))
$html = (Read-Text 'template.html').
    Replace('/*DATA*/', $data).
    Replace('/*ICONS*/', (Inline (ConvertTo-Json -InputObject $icons -Compress))).
    Replace('/*META*/', (Inline (Read-Text 'data\meta.json').Trim())).
    Replace('/*TALENTS*/', (Inline (Read-Text 'data\talents.json').Trim())).
    Replace('/*DOT*/', (Inline (Read-Text 'data\dot.json').Trim()))
[IO.File]::WriteAllText((Join-Path $Repo 'index.html'), $html, $Utf8)
Write-Host "index.html geschrieben: $($entries.Count) Eintraege, $($icons.Count) Icons"
