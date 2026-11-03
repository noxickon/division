# Erzeugt img\ und data\icons.json (ID -> Bildpfad im Repo) aus dem eigenen Hunter-Export, ohne fremde Quellen
#   Set- und Markenlogos: das Spritesheet nennt myIconSprite im .mgearset; welcher Ausschnitt, ergibt sich aus dem Sprite-Namen
#     (die Sprite-ID ist ein Hash, dessen Verfahren nicht in den Daten steht). Pruefung: gleiche ID -> gleicher Name.
#   Skill-Varianten: feste Zuordnung Variante -> Sprite-Name im ui_skill_spritesheet
#   Exotics, Named Weapons: myIcon im .mitem (oder einem Elternitem) -> generated icons\...png
# Die Spritesheets sind Masken (Rotkanal = Deckkraft); Logos und Skill-Icons werden weiss mit Transparenz gespeichert,
# die Kachelfarbe kommt aus dem CSS. Item-Bilder werden auf 160 x 80 verkleinert (Anzeige 76 x 40, doppelte Dichte).
# Aufruf: powershell -NoProfile -ExecutionPolicy Bypass -File tools\icons.ps1 [-Export <Ordner mit raw_files\ und images\>]
param([string]$Export = 'C:\Users\alex\Downloads\exported_files')
$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot -Parent
$Utf8 = New-Object Text.UTF8Encoding($false)
$Raw = Join-Path $Export 'raw_files'
$Img = Join-Path $Export 'images'
$H = Join-Path $Raw 'hunter\game system data'
$R = Join-Path $Raw 'rogue\game system data'
foreach ($p in $H, (Join-Path $Img 'hunter\baked\ui')) { if (-not (Test-Path -LiteralPath $p)) { throw "Export unvollstaendig, fehlt: $p" } }

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
public static class IconTool {
    static readonly Dictionary<string, Bitmap> Sheets = new Dictionary<string, Bitmap>();
    // Ausschnitt (UV-Rechteck 0..1) einer Masken-Textur als weisses Icon; Deckkraft = Rotkanal
    public static void Sprite(string sheet, double x, double y, double w, double h, string dst) {
        Bitmap src;
        if (!Sheets.TryGetValue(sheet, out src)) { src = new Bitmap(sheet); Sheets[sheet] = src; }
        int px = (int)Math.Round(x * src.Width), py = (int)Math.Round(y * src.Height);
        int pw = Math.Max(1, (int)Math.Round(w * src.Width)), ph = Math.Max(1, (int)Math.Round(h * src.Height));
        using (var outb = new Bitmap(pw, ph, PixelFormat.Format32bppArgb)) {
            for (int j = 0; j < ph; j++) for (int i = 0; i < pw; i++) {
                Color c = src.GetPixel(Math.Min(px + i, src.Width - 1), Math.Min(py + j, src.Height - 1));
                outb.SetPixel(i, j, Color.FromArgb(c.R * c.A / 255, 255, 255, 255));
            }
            outb.Save(dst, ImageFormat.Png);
        }
    }
    // Item-Bild verkleinern, Seitenverhaeltnis bleibt
    public static void Resize(string file, int width, string dst) {
        using (var src = new Bitmap(file)) {
            int height = (int)Math.Round((double)src.Height * width / src.Width);
            using (var outb = new Bitmap(width, height, PixelFormat.Format32bppArgb))
            using (var g = Graphics.FromImage(outb)) {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingMode = CompositingMode.SourceCopy;
                g.DrawImage(src, 0, 0, width, height);
                outb.Save(dst, ImageFormat.Png);
            }
        }
    }
}
'@

# Spritesheet: Sprite-Name -> UV-Rechteck (aus .spritesheet.decompiled) und Pfad der Textur im Bild-Export
$SheetCache = @{}
function Get-Sheet([string]$Path) {
    $key = $Path.ToLower()
    if ($SheetCache.ContainsKey($key)) { return $SheetCache[$key] }
    $file = Join-Path $Raw ($Path -replace '/', '\')
    $text = [IO.File]::ReadAllText("$file.decompiled")
    $sprites = [ordered]@{}
    # Ein Block je Sprite; manche Sheets haben zusaetzliche Felder (Farbe, Beschnitt)
    foreach ($block in [regex]::Matches($text, '\{([^{}]*myName = [^{}]*)\}')) {
        $f = @{}; foreach ($kv in [regex]::Matches($block.Groups[1].Value, '(my\w+) = ("[^"]*"|[^,\s]+)')) { $f[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim('"') }
        $sprites[$f.myName] = @{ h = [double]$f.myH; w = [double]$f.myW; x = [double]$f.myX; y = [double]$f.myY }
    }
    $png = Join-Path $Img (($(if ($text -match 'myTexture = "([^"]+)"') { $Matches[1] } else { throw "Textur fehlt in $file" })) -replace '/', '\' -replace '\.dds$', '.png')
    $sheet = @{ png = $png; sprites = $sprites }
    $SheetCache[$key] = $sheet
    return $sheet
}

# "mySpriteId = 123, mySpritesheet = F\"hunter/ui/spritesheets/x.spritesheet\"" aus einer Datei
function Get-SpriteRef([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return $null }
    if ([IO.File]::ReadAllText($File) -match 'myIconSprite "mySpriteId = (-?\d+), mySpritesheet = F\\"([^\\"]+)\\""') { return @{ id = [int64]$Matches[1]; sheet = $Matches[2] } }
    return $null
}

function Save-Sprite([string]$SheetPath, [string]$Name, [string]$Dst) {
    $sheet = Get-Sheet $SheetPath
    $s = $sheet.sprites[$Name]
    if (-not $s) { return $false }
    [IconTool]::Sprite($sheet.png, $s.x, $s.y, $s.w, $s.h, $Dst)
    return $true
}

# Logo-Sprites mit internem Codenamen statt Marken- oder Setnamen (per Bild geprueft)
$LogoAlias = @{
    'golan-gear-ltd' = 'gear_brands_golem'; 'gila-guard' = 'gear_brands_paladin'; 'empress-international' = 'gear_brands_monarch'
    'airaldi-holdings' = 'gear_brands_18'; 'murakami-industries' = 'gear_brands_19'; 'rigger' = 'gearset_field_hacker'
    'eclipse-protocol' = 'gearset_contagion'; 'hunters-fury' = 'gearset_shadow_killer'; 'aces-eights' = 'gearset_aces_hearts'
}
# Sonst: der Sprite-Name ohne Vorsilben steckt im Eintrags-ID (z. B. gear_brands_hanau -> hana-u-corporation); bei mehreren der kuerzeste
function Find-LogoSprite([string]$Id, $Sheet) {
    if ($LogoAlias.ContainsKey($Id)) { return $LogoAlias[$Id] }
    $plain = $Id -replace '[^a-z0-9]', ''
    $hits = foreach ($n in $Sheet.sprites.Keys) {
        $core = ($n.ToLower() -replace '^(gear_brands|gear_set|gearset|brands|brandset)_', '' -replace '_(gearset|brandset)$', '') -replace '[^a-z0-9]', ''
        if ($core.Length -ge 3 -and $plain.Contains($core)) { $n }
    }
    return @($hits | Sort-Object Length) | Select-Object -First 1
}

# Skill-Variante -> Sprite im ui_skill_spritesheet. Striker teilt sich im Spiel das Icon mit Crusader (gleiche Sprite-ID in den Tier-Dateien).
$SkillSheet = 'hunter/ui/spritesheets/ui_skill_spritesheet.spritesheet'
$SkillSprites = @{
    s_mod_shield_ballistic = 'skill_shield_ballistic'; s_mod_shield_ricochet = 'skill_shield_ricochet'; s_mod_shield_rifle = 'skill_shield_rifle'; s_mod_shield_rifle_buff = 'skill_shield_rifle'
    s_mod_chemlauncher_corrosive_cloud = 'skill_chemlauncher_corrosive'; s_mod_chemlauncher_explosive_vapor = 'skill_chemlauncher_explosive'
    s_mod_chemlauncher_repair_cloud = 'skill_chemlauncher_repair'; s_mod_chemlauncher_riot_foam = 'skill_chemlauncher_riotfoam'
    s_mod_decoy_distraction = 'skill_decoy'
    s_mod_drone_assault = 'skill_drone_assault'; s_mod_drone_bombardier = 'skill_drone_bomb'; s_mod_drone_protector = 'skill_drone_guardian'
    s_mod_drone_surveyor = 'skill_drone_surveyor'; s_mod_drone_repair = 'skill_drone_repair'; s_mod_drone_gas_bomber = 'skill_drone_gas'; s_mod_drone_trophy_system = 'skill_drone_trophy'
    s_mod_firefly_blind = 'skill_firefly_blind'; s_mod_firefly_hardpoint = 'skill_firefly_hardpoint'; s_mod_firefly_magnetic_shrapnel = 'skill_firefly_shrapnel'
    s_mod_hive_repair = 'skill_hive_armor'; s_mod_hive_revive = 'skill_hive_revive'; s_mod_hive_stims = 'skill_hive_stims'; s_mod_hive_wasp_nest = 'skill_hive_nest'
    s_mod_hive_tech = 'skill_hive_tech'; s_mod_hive_leech = 'skill_hive_leech'
    s_mod_pulse_echo = 'skill_pulse'; s_mod_pulse_emp = 'skill_pulse_emp'; s_mod_pulse_sensor = 'skill_pulse_thrown'; s_mod_pulse_achilles = 'skill_pulse_achilles'
    s_mod_pulse_banshee = 'skill_pulse_banshee'; s_mod_pulse_howl = 'skill_pulse_howl'
    s_mod_seekermine_airburst = 'skill_mine_airburst'; s_mod_seekermine_cluster = 'skill_mine_cluster'; s_mod_seekermine_explosive = 'skill_mine_explosive'
    s_mod_seekermine_repair = 'skill_mine_guardian'; s_mod_seekermine_blackout = 'skill_mine_blackout'
    s_mod_smartcover_fortified = 'skill_smart_cover_fortified'; s_mod_smartcover_precision = 'skill_smart_cover_precision'
    s_mod_stickybomb_burn = 'skill_stickybomb_burn'; s_mod_stickybomb_emp = 'skill_stickybomb_emp'; s_mod_stickybomb_explosive = 'skill_stickybomb_explosive'
    s_mod_trap_explosive = 'skill_trap_explosive'; s_mod_trap_repair = 'skill_trap_heal'; s_mod_trap_shock = 'skill_trap_shock'; s_mod_trap_corrosive = 'skill_trap_corrosive'
    s_mod_turret_assault = 'skill_turret_assault'; s_mod_turret_flamer = 'skill_turret_flamer'; s_mod_turret_sniper = 'skill_turret_sniper'; s_mod_turret_mortar = 'skill_turret_mortar'
}

# Item-Bilder im Export, nach Dateiname (klein, ohne Endung und ohne "_icon")
$ItemPics = @{}
foreach ($p in Get-ChildItem -LiteralPath (Join-Path $Img 'hunter\baked\ui\loose_images\generated icons') -Recurse -Filter '*.png') {
    $base = $p.BaseName.ToLower()
    foreach ($k in $base, ($base -replace '_icon$', '')) { if (-not $ItemPics.ContainsKey($k)) { $ItemPics[$k] = $p.FullName } }
}
function Find-Pic([string]$Name) {
    if (-not $Name) { return $null }
    $k = [IO.Path]::GetFileNameWithoutExtension(($Name -replace '\\', '/').Split('/')[-1]).ToLower() -replace '_icon$', ''
    return $ItemPics[$k]
}
# Item-Bild: das Item selbst, dann seine Elternitems ("WeaponItem x < uid=.. > : parent"). Je Stufe:
#   myIcon / myInventoryIcon -> "<item>" -> "<item>_<Modell>" (myMaleVisualGearName) -> Waffendatei (myInventoryIcon, sonst Modell myGraphObject)
function Find-ItemIcon([string]$Name) {
    $cur = $Name
    for ($i = 0; $i -lt 8 -and $cur; $i++) {
        $file = @((Join-Path $H "juice\item\$cur.mitem"), (Join-Path $R "juice\item\$cur.mitem")) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $file) { return $null }
        $text = [IO.File]::ReadAllText($file)
        foreach ($m in [regex]::Matches($text, '(?m)^\s*my(?:Inventory)?Icon "?([^"\r\n]+\.dds)')) { $pic = Find-Pic $m.Groups[1].Value; if ($pic) { return $pic } }
        $pic = Find-Pic $cur; if ($pic) { return $pic }
        if ($text -match 'myMaleVisualGearName "[^"]*/([^/"]+)\.mgraphobject"') { $pic = Find-Pic "$($cur)_$($Matches[1])"; if ($pic) { return $pic } }
        foreach ($inc in [regex]::Matches($text, '(?m)^include "([^"]+\.mweapon)"')) {
            $wp = Join-Path $Raw ($inc.Groups[1].Value -replace '/', '\')
            if (-not (Test-Path -LiteralPath $wp)) { continue }
            $wt = [IO.File]::ReadAllText($wp)
            if ($wt -match '(?m)^\s*myInventoryIcon "?([^"\r\n]+\.dds)') { $pic = Find-Pic $Matches[1]; if ($pic) { return $pic } }
            if ($wt -match '(?m)^\s*myGraphObject "([^"]+)"') { $pic = Find-Pic $Matches[1]; if ($pic) { return $pic } }
        }
        $cur = if ($text -match '(?m)^\w+ \S+ < uid=[0-9A-F]{32} > : (\S+)') { $Matches[1] } else { $null }
    }
    return $null
}

$Out = Join-Path $Repo 'img'
foreach ($d in 'logos', 'skills', 'items') { [void](New-Item -ItemType Directory -Force (Join-Path $Out $d)) }
$icons = [ordered]@{}
$missing = New-Object System.Collections.Generic.List[string]

# Sets und Marken; gleiche Sprite-ID muss denselben Sprite-Namen ergeben, verschiedene IDs verschiedene Namen
$byId = @{}; $byName = @{}
foreach ($f in 'gearsets', 'brandsets') {
    foreach ($e in (ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $Repo "data\$f.json"), $Utf8)))) {
        $id = [string]$e.id
        $ref = Get-SpriteRef (Join-Path $H ([string]$e.source))
        $name = if ($ref) { Find-LogoSprite $id (Get-Sheet $ref.sheet) } else { $null }
        if (-not $name -or -not (Save-Sprite $ref.sheet $name (Join-Path $Out "logos\$id.png"))) { $missing.Add("$f/$id"); continue }
        $icons[$id] = "img/logos/$id.png"
        $key = "$($ref.sheet.ToLower())|$name"
        if ($byId.ContainsKey($ref.id) -and $byId[$ref.id] -ne $key) { Write-Warning "$id`: Sprite-ID $($ref.id) schon $($byId[$ref.id]), jetzt $key" }
        if ($byName.ContainsKey($key) -and $byName[$key] -ne $ref.id) { Write-Warning "$id`: Sprite $key schon mit ID $($byName[$key])" }
        $byId[$ref.id] = $key; $byName[$key] = $ref.id
    }
}

# Skill-Varianten
foreach ($s in (ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $Repo 'data\skills.json'), $Utf8)))) {
    foreach ($v in $s.variants) {
        $id = [string]$v.id
        $name = $SkillSprites[$id]
        if ($name -and (Save-Sprite $SkillSheet $name (Join-Path $Out "skills\$id.png"))) { $icons[$id] = "img/skills/$id.png" } else { $missing.Add("skills/$id") }
    }
}

# Exotics und Named Weapons
foreach ($f in 'exotics', 'namedweapons') {
    foreach ($e in (ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $Repo "data\$f.json"), $Utf8)))) {
        $png = Find-ItemIcon ([IO.Path]::GetFileNameWithoutExtension([string]$e.source))
        if ($png) { [IconTool]::Resize($png, 160, (Join-Path $Out "items\$($e.id).png")); $icons[[string]$e.id] = "img/items/$($e.id).png" } else { $missing.Add("$f/$($e.id)") }
    }
}

# Bilder, die zu keiner ID mehr gehoeren, entfernen
$keep = @{}; foreach ($p in $icons.Values) { $keep[(Join-Path $Repo ($p -replace '/', '\')).ToLower()] = $true }
foreach ($old in Get-ChildItem $Out -Recurse -File) { if (-not $keep.ContainsKey($old.FullName.ToLower())) { Remove-Item -LiteralPath $old.FullName } }

[IO.File]::WriteAllText((Join-Path $Repo 'data\icons.json'), (ConvertTo-Json -InputObject $icons), $Utf8)
$size = (Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("data\icons.json: {0} Icons ({1:N1} MB), ohne Icon: {2}" -f $icons.Count, ($size / 1MB), $missing.Count)
if ($missing.Count) { Write-Host ('  ' + ($missing -join ', ')) }
