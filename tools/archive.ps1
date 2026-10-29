# Sichert das "Wissens-Set" eines Hunter-Exports (Raw Files) pro Spiel-Build in ein schlankes, durchsuchbares Archiv.
# Unveraenderte Dateien werden per Hardlink mit dem vorherigen Build geteilt (kein zusaetzlicher Platz),
# jeder Build-Ordner bleibt trotzdem vollstaendig und direkt durchsuchbar.
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\archive.ps1 [-Export <raw_files>] [-Archive <ordner>] [-Build <yyyy-mm-dd>]
# Ergebnis: <Archive>\builds\<build>\files\...    das Wissens-Set (gleiche Pfade wie im Export)
#           <Archive>\builds\<build>\manifest.csv  Pfad, Groesse, SHA1 jeder behaltenen Datei
#           <Archive>\builds\<build>\changes.csv   added/changed/removed gegenueber dem vorherigen Build
#           <Archive>\builds\<build>\dropped.csv.gz Pfad und Groesse jeder weggelassenen Datei
#           <Archive>\builds\<build>\info.json     Build, Datum, Zahlen
param(
    [string]$Export = (Join-Path $env:USERPROFILE 'Downloads\exported_files\raw_files'),
    [string]$Archive = 'D:\DivisionArchive',
    [string]$Build = '',
    [string]$Game = "D:\UbisoftLibrary\Tom Clancy's The Division 2"
)
$ErrorActionPreference = 'Stop'
function Log([string]$Msg) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Msg) }

Add-Type -Namespace Win32 -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);
'@

# ---------- Was behalten wird (siehe docs/datamining.md, Abschnitt Archiv) ----------
# Ganze Ordner, relativ zu raw_files
$KeepDirs = @(
    'hunter\game system data', 'rogue\game system data',          # Talente, Items, Formeln, Waffen, Loot
    'hunter\skillscript', 'rogue\skillscript',                    # Talent- und Skill-Logik
    'hunter\localization\packages\german', 'hunter\localization\packages\english',
    'hunter\nodes', 'rogue\nodes', 'snowdrop\nodes',              # Bausteine der Skillscripts (Schaden, Status, Talentregeln)
    'hunter\contentscripts', 'rogue\contentscripts',              # Open-World-Aktivitaeten
    'hunter\interaction', 'rogue\interaction',                    # von den Spieldaten eingebunden
    'snowdrop\modules',                                           # Schemas
    'hunter\scripts'                                              # Boss-, Raid- und Missionsskripte
)
# Karten: nur Text-Ebenen (Platzierungen, Zonen, Lesezeichen), keine Geometrie und keine Gelaendetexturen
$MapRoots = @('hunter\maps', 'rogue\maps')
function Test-KeepMapFile([string]$Rel) {
    if ($Rel -match '\\(terrainvirtualtexture|terrainvttiles)\\') { return $false }
    return $Rel -match '\.(mlayer|juice)$'
}

# ---------- Build bestimmen ----------
if (-not $Build) {
    $toc = Join-Path $Game 'hunter\sdf\pc\data\sdf.sdftoc'
    if (-not (Test-Path -LiteralPath $toc)) { throw "Build unbekannt: $toc fehlt. -Build angeben." }
    $b = New-Object byte[] 64
    $fs = [IO.File]::OpenRead($toc); [void]$fs.Read($b, 0, 64); $fs.Close()
    $Build = '{0:D4}-{1:D2}-{2:D2}' -f [BitConverter]::ToUInt16($b, 0x24), [BitConverter]::ToUInt16($b, 0x26), [BitConverter]::ToUInt16($b, 0x28)
    Log "Build laut Spielordner: $Build (stimmt nur, wenn der Export nach dem letzten Update gemacht wurde)"
}
$Export = (Resolve-Path -LiteralPath $Export).Path.TrimEnd('\')
$buildsDir = Join-Path $Archive 'builds'
$target = Join-Path $buildsDir $Build
if (Test-Path -LiteralPath (Join-Path $target 'manifest.csv')) { throw "Build $Build ist schon archiviert: $target" }
New-Item -ItemType Directory -Force -Path (Join-Path $target 'files') | Out-Null

# ---------- Vorheriger Build (fuer Hardlinks und Aenderungsliste) ----------
$prev = $null; $prevIndex = @{}
$older = @(Get-ChildItem -LiteralPath $buildsDir -Directory | Where-Object { $_.Name -lt $Build -and (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.csv')) } | Sort-Object Name)
if ($older.Count -gt 0) {
    $prev = $older[-1]
    foreach ($row in Import-Csv -LiteralPath (Join-Path $prev.FullName 'manifest.csv')) { $prevIndex[$row.path] = $row }
    Log "Vorheriger Build: $($prev.Name) ($($prevIndex.Count) Dateien)"
}

# ---------- Dateien sammeln ----------
$keep = New-Object System.Collections.Generic.List[string]
foreach ($d in $KeepDirs) {
    $abs = Join-Path $Export $d
    if (-not (Test-Path -LiteralPath $abs)) { Log "Fehlt im Export: $d"; continue }
    foreach ($f in [IO.Directory]::EnumerateFiles($abs, '*', 'AllDirectories')) { $keep.Add($f.Substring($Export.Length + 1)) }
}
foreach ($m in $MapRoots) {
    $abs = Join-Path $Export $m
    if (-not (Test-Path -LiteralPath $abs)) { continue }
    foreach ($f in [IO.Directory]::EnumerateFiles($abs, '*', 'AllDirectories')) { $rel = $f.Substring($Export.Length + 1); if (Test-KeepMapFile $rel) { $keep.Add($rel) } }
}
Log "Wissens-Set: $($keep.Count) Dateien"

# ---------- Kopieren bzw. verlinken, Manifest schreiben ----------
$sha = [Security.Cryptography.SHA1]::Create()
$manifest = New-Object System.Collections.Generic.List[string]
$manifest.Add('path,size,sha1')
$changes = New-Object System.Collections.Generic.List[string]
$changes.Add('change,path,size')
$seen = @{}
$linked = 0; $copied = 0; $bytesNew = [long]0; $bytesAll = [long]0; $i = 0
foreach ($rel in $keep) {
    $i++
    if ($i % 10000 -eq 0) { Log "  $i / $($keep.Count)" }
    $src = Join-Path $Export $rel
    $dst = Join-Path $target "files\$rel"
    $size = (New-Object IO.FileInfo $src).Length
    $stream = [IO.File]::OpenRead($src)
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') } finally { $stream.Close() }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
    $old = $prevIndex[$rel]
    $done = $false
    if ($old -and $old.sha1 -eq $hash) {
        $prevFile = Join-Path $prev.FullName "files\$rel"
        $done = [Win32.Native]::CreateHardLink($dst, $prevFile, [IntPtr]::Zero)
        if ($done) { $linked++ }
    }
    if (-not $done) {
        [IO.File]::Copy($src, $dst, $true); $copied++; $bytesNew += $size
        if ($prev) { $changes.Add(('{0},"{1}",{2}' -f $(if ($old) { 'changed' } else { 'added' }), $rel, $size)) }
    }
    $bytesAll += $size
    $seen[$rel] = $true
    $manifest.Add(('"{0}",{1},{2}' -f $rel, $size, $hash))
}
if ($prev) { foreach ($k in $prevIndex.Keys) { if (-not $seen.ContainsKey($k)) { $changes.Add(('removed,"{0}",{1}' -f $k, $prevIndex[$k].size)) } } }
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllLines((Join-Path $target 'manifest.csv'), $manifest, $utf8)
[IO.File]::WriteAllLines((Join-Path $target 'changes.csv'), $changes, $utf8)
Log "Kopiert: $copied ($([math]::Round($bytesNew / 1MB)) MB neu), verlinkt: $linked, gesamt $([math]::Round($bytesAll / 1MB)) MB"

# ---------- Liste der weggelassenen Dateien (Pfad + Groesse), gepackt ----------
Log 'Liste der weggelassenen Dateien ...'
$keepSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($k in $keep) { [void]$keepSet.Add($k) }
$gzPath = Join-Path $target 'dropped.csv.gz'
$out = [IO.File]::Create($gzPath)
$gz = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionMode]::Compress)
$w = New-Object IO.StreamWriter($gz, $utf8)
$w.WriteLine('path,size')
$dropped = 0; $droppedBytes = [long]0
try {
    foreach ($f in [IO.Directory]::EnumerateFiles($Export, '*', 'AllDirectories')) {
        $rel = $f.Substring($Export.Length + 1)
        if ($keepSet.Contains($rel)) { continue }
        $len = (New-Object IO.FileInfo $f).Length
        $w.WriteLine(('"{0}",{1}' -f $rel, $len)); $dropped++; $droppedBytes += $len
    }
} finally { $w.Close() }
Log "Weggelassen: $dropped Dateien, $([math]::Round($droppedBytes / 1GB, 1)) GB"

$info = [ordered]@{
    build = $Build; archived = (Get-Date -Format 'yyyy-MM-dd HH:mm'); export = $Export; previousBuild = $(if ($prev) { $prev.Name } else { $null })
    files = $keep.Count; megabytes = [math]::Round($bytesAll / 1MB); newMegabytes = [math]::Round($bytesNew / 1MB)
    copied = $copied; hardlinked = $linked; changes = $changes.Count - 1; droppedFiles = $dropped; droppedGigabytes = [math]::Round($droppedBytes / 1GB, 1)
    keepDirs = $KeepDirs; mapRoots = $MapRoots
}
[IO.File]::WriteAllText((Join-Path $target 'info.json'), (ConvertTo-Json $info -Depth 4), $utf8)
Log "Fertig: $target"
