# Erzeugt data/*.json fuer die Division-Page direkt aus einem Hunter-Export (Raw Files) von The Division 2.
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\extract.ps1 [-Export <raw_files>] [-Version 23]
# Ausgabe: data/gearsets.json, data/brandsets.json, data/exotics.json, data/namedweapons.json, data/talents.json, data/dot.json, data/formulas.json, data/meta.json
param(
    [string]$Export = (Join-Path $env:USERPROFILE 'Downloads\exported_files\raw_files'),
    [int]$Version = 0,
    [string]$Game = "D:\UbisoftLibrary\Tom Clancy's The Division 2"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'juice.ps1')

$Repo = Split-Path $PSScriptRoot -Parent
$H = Join-Path $Export 'hunter\game system data'
$R = Join-Path $Export 'rogue\game system data'
$Configs = Join-Path $H 'juice\itemgeneration\configs'
$Culture = @{ de = [Globalization.CultureInfo]'de-DE'; en = [Globalization.CultureInfo]'en-US' }

function Log([string]$Msg) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Msg) }

# Neueste Itemgenerierungs-Version (code1_dataN) ist die, mit der aktuell neue Items erzeugt werden
if ($Version -eq 0) {
    $Version = (Get-ChildItem $Configs -Filter 'configs_code1_data*.mitemgenerationconfigs' | ForEach-Object { [int]($_.BaseName -replace '.*data', '') } | Measure-Object -Maximum).Maximum
}
Log "Itemgenerierung: Version data$Version"

# ---------- Lokalisierung ----------
$Loc = @{
    de = Read-Locpack (Join-Path $Export 'hunter\localization\packages\german\menus.locpack')
    en = Read-Locpack (Join-Path $Export 'hunter\localization\packages\english\menus.locpack')
}
Log "Lokalisierung: $($Loc.de.Count) deutsche, $($Loc.en.Count) englische Texte"

function Clean-Text([string]$Text) {
    if (-not $Text) { return $Text }
    $t = $Text -replace '-<br\s*/?>', '' -replace '<br\s*/?>', ' ' -replace '<color[^>]*>(.*?)</color>', '**$1**' -replace '<[^>]+>', ''
    return ($t -replace '\*\*(\s*)\*\*', '$1' -replace '[ \t]+\n', "`n").Trim()
}

# Namen ohne Hervorhebungen
function Clean-Name($Loc) {
    if (-not $Loc) { return $null }
    return [ordered]@{ de = (Clean-Text $Loc.de) -replace '\*\*', ''; en = (Clean-Text $Loc.en) -replace '\*\*', '' }
}

# @{ de; en } fuer ein Lokalisierungsfeld; faellt auf den Quelltext zurueck
function Get-Loc([string]$Raw) {
    $f = Get-LocField $Raw
    if (-not $f) { return $null }
    $en = if ($f.guid -and $Loc.en.ContainsKey($f.guid)) { $Loc.en[$f.guid] } else { $f.text }
    $de = if ($f.guid -and $Loc.de.ContainsKey($f.guid)) { $Loc.de[$f.guid] } else { $en }
    if (-not $en -or $en -match '^\|?empty\|?$|INSERT TEXT') { return $null }
    return [ordered]@{ de = $de; en = $en }
}

function Format-Number([double]$Value, [string]$Lang) {
    return ([math]::Round($Value, 2)).ToString('0.##', $Culture[$Lang])
}

# Ersetzt {0}, {1} ... durch Werte; vor einem %-Zeichen werden Anteile (0.2) zu Prozent (20)
function Format-Tooltip([string]$Text, $Values, [string]$Lang) {
    if (-not $Text) { return $null }
    $t = Clean-Text $Text
    $t = [regex]::Replace($t, '\{(\d+)\}(\s?%)?', {
        param($m)
        $i = [int]$m.Groups[1].Value
        if ($i -ge $Values.Count -or $null -eq $Values[$i]) { return '?' + $m.Groups[2].Value }
        $v = [math]::Abs([double]$Values[$i])
        if ($m.Groups[2].Success -and $v -le 10) { $v = $v * 100 }
        return (Format-Number $v $Lang) + $m.Groups[2].Value
    })
    return $t
}

# ---------- Attribute (Formel-Woerterbuecher) ----------
$Attr = @{}      # uid -> @{ name; label; bonusType; formula }
$AttrByName = @{}
$formulas = New-Object System.Collections.Generic.List[object]
foreach ($dir in (Join-Path $R 'juice\attribute\dictionary'), (Join-Path $H 'juice\attribute\dictionary')) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $dir -Filter *.mdict) {
        $root = Read-Juice $file.FullName
        foreach ($def in Find-Kids $root 'AttributeDefinition') {
            $specs = foreach ($s in $def.kids | Where-Object { $_.kw -eq 'mySpecializations' } | ForEach-Object { $_.kids }) {
                [ordered]@{ name = $s.name; condition = Get-Prop $s 'myCondition'; formula = Get-Prop $s 'myFormula' }
            }
            $a = [ordered]@{
                uid = $def.uid; name = $def.name; dict = $file.BaseName
                label = Get-Loc (Get-Prop $def 'myUIName')
                bonusType = Get-Prop $def 'myBonusType'
                formula = Get-Prop $def 'myOriginalFormula'
                specializations = @($specs)
            }
            if ($def.uid) { $Attr[$def.uid] = $a }
            $AttrByName[$def.name] = $a
            $formulas.Add($a)
        }
    }
}
Log "Attribute: $($Attr.Count) mit UID, $($formulas.Count) Formeln"

function Get-AttrLabel([string]$Name) {
    $a = $AttrByName[$Name]
    if ($a -and $a.label) { return Clean-Name $a.label }
    $human = ($Name -replace '(Final|ModBonus|FlatBonus|Bonus)$', '' -replace '([a-z])([A-Z])', '$1 $2' -replace '_', ' ').Trim()
    return [ordered]@{ de = $human; en = $human }
}

# Wert eines Set-/Talentbonus fuer die Anzeige: Prozent-Attribute als %, sonst Zahl
function Get-BonusValue([string]$AttrName, [double]$Value) {
    $a = $AttrByName[$AttrName]
    $type = if ($a) { $a.bonusType } else { $null }
    $isPercent = $type -in 'Percentage', 'Modifier' -or ($null -eq $type -and $AttrName -match 'ModBonus|Percentage|Mod$')
    if ($isPercent) { return [ordered]@{ value = [math]::Round($Value * 100, 2); unit = '%' } }
    return [ordered]@{ value = [math]::Round($Value, 2); unit = $null }
}

# ---------- Skalierung: welcher Schadens-Topf wird beruehrt ----------
$Buckets = [ordered]@{
    totalWeaponDamage = '^GearTalentWeaponDamageModBonus'
    weaponDamage      = '^(WeaponDamageModBonus|TalentWeaponDamageModBonus|TalentInterfaceWeaponDamageModBonus|GlobalWeaponDamageModBonus|(AssaultRifle|LMG|SMG|Shotgun|Pistol|Rifle|MarksmanRifle|Revolver)DamageModBonus|WeaponDamageBaseModBonus)'
    critChance        = 'CriticalHitChance'
    critDamage        = 'CriticalHitDamage'
    headshot          = 'WeaponDamageMultiplierHead'
    outOfCover        = 'OutOfCover'
    damageToArmor     = 'DamageDoneToArmor|ArmorDamageModifier'
    damageToHealth    = 'DamageDoneToHealth|DamageMultiplierHealth'
    statusEffects     = '^(AllStatusEffectsModBonus|Burn|Bleed|Poison|Shock|Blind|Ensnare|Confuse)'
    skill             = '^(allskills_|SkillPower|Skill)'
    armor             = '^(Armor(Gear|Regen|OnKill|Repair|Mod)|BonusArmor|TotalArmor)'
}
$TextBuckets = [ordered]@{
    totalWeaponDamage = 'total weapon damage'
    weaponDamage      = '(?<!total )weapon damage'
    amplified         = 'amplif'
    critChance        = 'critical hit chance'
    critDamage        = 'critical hit damage'
    headshot          = 'headshot damage'
    statusEffects     = 'status effect|bleed|burn|poison|shock|blind|ensnare|disorient'
    skill             = 'skill (damage|tier|repair|haste|efficiency)|skill'
}
function Get-Scales([string[]]$AttrNames, [string]$EnText) {
    $set = New-Object System.Collections.Generic.List[string]
    foreach ($n in $AttrNames) { foreach ($k in $Buckets.Keys) { if ($n -match $Buckets[$k] -and -not $set.Contains($k)) { $set.Add($k) } } }
    if ($EnText) { $lower = $EnText.ToLower(); foreach ($k in $TextBuckets.Keys) { if ($lower -match $TextBuckets[$k] -and -not $set.Contains($k)) { $set.Add($k) } } }
    return ,$set.ToArray()
}

# ---------- Statuseffekt-Quellen: welches Talent loest welchen Statuseffekt aus ----------
# Talentregeln (ApplyStatusEffect) und Skillscripts (ApplyStatusEffectNode). Ohne myDamageOverride gilt der Standardschaden.
$StatusNames = @{}
foreach ($f in Get-ChildItem (Join-Path $R 'juice\statuseffects') -Filter *.mstatuseffect) {
    $txt = [IO.File]::ReadAllText($f.FullName)
    if ($txt -match '(?m)^StatusEffect (\S+) < uid=([0-9A-F]{32})') { $StatusNames[$Matches[2]] = $Matches[1] }
}
$StatusBySource = @{}   # Talentregel- oder Skillscript-Name -> @(@{ status; override })
foreach ($ruleFile in Get-ChildItem (Join-Path $H 'juice\talentrules') -Filter *.mtalentrules) {
    $txt = [IO.File]::ReadAllText($ruleFile.FullName)
    if ($txt -notmatch 'ApplyStatusEffect') { continue }
    foreach ($a in Find-Kids (Read-Juice $ruleFile.FullName) 'ApplyStatusEffect') {
        $ref = $a.props | Where-Object { $_ -match '^myStatusEffect ' } | ForEach-Object { Get-Ref $_ } | Select-Object -First 1
        $dmg = Get-Prop $a 'myDamageOverride'
        if ($ref) { $StatusBySource[$ruleFile.BaseName] += @(@{ status = $ref.name; override = $(if ($dmg -and $dmg -ne '-1') { $dmg } else { $null }) }) }
    }
}
foreach ($dir in (Join-Path $Export 'hunter\skillscript'), (Join-Path $Export 'rogue\skillscript')) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($g in Get-ChildItem $dir -Filter *.decompiled -Recurse) {
        $txt = [IO.File]::ReadAllText($g.FullName)
        if ($txt -notmatch 'ApplyStatusEffectNode') { continue }
        $name = $g.Name -replace '\.mskillscriptgraph\.decompiled$', ''
        foreach ($m in [regex]::Matches($txt, 'value = \{\s*#&([0-9A-F]{32}),\s*\},\s*valueType = "RShared:StatusEffect"')) {
            $s = $StatusNames[$m.Groups[1].Value]
            if ($s) { $StatusBySource[$name] += @(@{ status = $s; override = $null }) }
        }
    }
}
Log "Statuseffekt-Quellen: $($StatusBySource.Count) Talentregeln/Skillscripts"

# Statuseffekte, die ein Talent ueber seine Talentregeln oder seinen Skillscript ausloest
function Get-AppliedStatus([string]$TalentText) {
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($m in [regex]::Matches($TalentText, '(myTalentRules|mySkillScript) <[^>]*> = ("[^"]+"|\S+)')) {
        foreach ($s in @($StatusBySource[$m.Groups[2].Value.Trim('"')])) {
            if ($s -and -not ($found | Where-Object { $_.status -eq $s.status })) { $found.Add([ordered]@{ status = $s.status; custom = [bool]$s.override }) }
        }
    }
    return ,$found.ToArray()
}

# Skillscripts enthalten oft eine Liste aller Statuseffekte, auf die sie reagieren; ausgeloest wird nur, was der Talenttext nennt
$StatusWords = @{ Burn = 'burn|fire|ignit'; Bleed = 'bleed'; Poison = 'poison'; Shock = 'shock'; Blind = 'blind'; Confuse = 'disorient|confus'; Ensnare = 'ensnare'; Disrupt = 'disrupt' }
function Select-Mentioned($Applied, [string]$Text) {
    if (@($Applied).Count -le 1 -or -not $Text) { return ,@($Applied) }
    $lower = $Text.ToLower()
    $hit = @($Applied | Where-Object { $StatusWords[$_.status] -and $lower -match $StatusWords[$_.status] })
    if ($hit.Count -gt 0) { return ,$hit } else { return ,@($Applied) }
}

# ---------- Talente ----------
$TalentDir = Join-Path $H 'juice\talent'
$TalentCache = @{}
function Read-BonusList($ListNode) {
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $ListNode) { return $out }
    foreach ($b in $ListNode.kids) {
        $uid = Get-Prop $b 'myAttributeUID'
        $raw = Get-Prop $b 'myValue'
        if ($null -eq $raw) { $raw = Get-Prop $b 'myC' }
        $value = $null
        if ($raw -and [double]::TryParse($raw, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { } else { $value = $null }
        $name = if ($uid -and $Attr[$uid]) { $Attr[$uid].name } else { $b.name }
        $out.Add(@{ uid = $uid; attr = $name; value = $value })
    }
    return $out
}

function Get-Talent([string]$Id) {
    if ($TalentCache.ContainsKey($Id)) { return $TalentCache[$Id] }
    $path = Join-Path $TalentDir "$Id.mtalent"
    if (-not (Test-Path -LiteralPath $path)) { $TalentCache[$Id] = $null; return $null }
    $root = Read-Juice $path
    $node = $root.kids | Where-Object { $_.kw -eq 'Talent' } | Select-Object -First 1
    if (-not $node) { $TalentCache[$Id] = $null; return $null }
    $pve = Read-BonusList (Get-Kid $node 'myBonusList')
    $pvp = $null
    $ov = Get-Kid $node 'myTalentOverrides'
    if ($ov) {
        foreach ($o in $ov.kids) {
            if ($o.name -match 'PVP' -and (Get-Prop $o 'myUseOverrideBonusList') -eq 'TRUE') {
                $list = Read-BonusList (Get-Kid $o 'myOverrideBonusList')
                # PvP-Werte in die Reihenfolge der PvE-Liste bringen (Platzhalter zaehlen nach dieser Reihenfolge)
                $pvp = foreach ($p in $pve) { $hit = $list | Where-Object { $_.uid -and $_.uid -eq $p.uid } | Select-Object -First 1; if ($hit) { $hit.value } else { $p.value } }
            }
        }
    }
    $name = Clean-Name (Get-Loc (Get-Prop $node 'myUIName'))
    $tipField = Get-LocField (Get-Prop $node 'myToolTipText')
    $tip = Get-Loc (Get-Prop $node 'myToolTipText')
    $values = @($pve | ForEach-Object { $_.value })
    $text = $null; $textPvp = $null
    if ($tip) {
        $text = [ordered]@{ de = Format-Tooltip $tip.de $values 'de'; en = Format-Tooltip $tip.en $values 'en' }
        if ($pvp) {
            $pv = @($pvp)
            $candidate = [ordered]@{ de = Format-Tooltip $tip.de $pv 'de'; en = Format-Tooltip $tip.en $pv 'en' }
            if ($candidate.en -ne $text.en) { $textPvp = $candidate }
        }
    }
    # Bedingung, damit das Talent wirkt (z. B. "Benoetigt 9 rote Kern-Attribute"); deaktivierte Texte ignorieren
    $reqRaw = Get-Prop $node 'myRequirementsText'
    $requirement = $null
    if ($reqRaw -and $reqRaw -notmatch 'enabled = false') {
        $req = Get-Loc $reqRaw
        if ($req) { $requirement = [ordered]@{ de = Format-Tooltip $req.de $values 'de'; en = Format-Tooltip $req.en $values 'en' } }
    }
    $attrs = @($pve | ForEach-Object { $_.attr } | Where-Object { $_ } | Select-Object -Unique)
    $t = [ordered]@{
        id = $Id
        name = $name
        text = $text
        textPvp = $textPvp
        requirement = $requirement
        applies = Select-Mentioned (Get-AppliedStatus ($node.props -join "`n")) $(if ($tip) { $tip.en } else { '' })
        attrs = $attrs
        scales = Get-Scales $attrs $(if ($tip) { $tip.en } else { $null })
    }
    $TalentCache[$Id] = $t
    return $t
}

# Kopie eines Talents mit vorangestelltem Slot
function With-Slot([string]$Slot, $Talent) {
    $out = [ordered]@{ slot = $Slot }
    foreach ($k in $Talent.Keys) { $out[$k] = $Talent[$k] }
    return $out
}

# ---------- Itemgenerierung (Item -> Talente/Attribute) ----------
$ConfigByLink = @{}
$UsedTalentLists = @{}   # Talentlisten, aus denen aktuelle Items wuerfeln (auch in Vorlagen ohne eigene Verknuepfung)
foreach ($file in Get-ChildItem $Configs -Filter "*_code1_data$Version.mitemgenerationconfigs") {
    $root = Read-Juice $file.FullName
    foreach ($cfg in $root.kids | Where-Object { $_.kw -eq 'ItemGenerationConfig' }) {
        foreach ($lists in Find-Kids $cfg 'myPossibleTalentLists') {
            foreach ($line in $lists.props) { $ref = Get-Ref $line; if ($ref) { $UsedTalentLists[$ref.name] = $true } }
        }
        $linkLine = $cfg.props | Where-Object { $_.StartsWith('myItemGenerationConfigLink ') } | Select-Object -First 1
        $link = if ($linkLine) { (Get-Ref $linkLine).name } else { $null }
        if (-not $link) { continue }
        $talents = New-Object System.Collections.Generic.List[object]
        foreach ($slot in Find-Kids $cfg 'ItemTalentSlot') {
            $line = $slot.props | Where-Object { $_.StartsWith('myPresetTalent ') } | Select-Object -First 1
            if ($line) { $ref = Get-Ref $line; if ($ref) { $talents.Add(@{ slot = $slot.name; id = $ref.name; named = ((Get-Prop $slot 'myIsNamedTalent') -eq 'TRUE') }) } }
        }
        $attrs = New-Object System.Collections.Generic.List[object]
        foreach ($slot in Find-Kids $cfg 'ItemAttributeSlot') {
            $uid = Get-Prop $slot 'myPresetAttribute'
            if ($uid -and $uid -notmatch '^0+$' -and $Attr[$uid]) {
                $attrs.Add(@{ slot = $slot.name; attr = $Attr[$uid].name; core = ((Get-Prop $slot 'myIsCoreAttribute') -eq 'TRUE') })
            }
        }
        $qualities = @(Find-Kids $cfg 'QualityTalentSlots' | ForEach-Object { Get-Prop $_ 'myQuality' })
        # Dieselbe Verknuepfung kann in mehreren Dateien stehen; die Variante mit Talenten/Attributen gewinnt
        $prev = $ConfigByLink[$link]
        if ($prev -and ($prev.talents.Count + $prev.attrs.Count) -ge ($talents.Count + $attrs.Count)) { continue }
        $ConfigByLink[$link] = @{ name = $cfg.name; file = $file.Name; talents = $talents; attrs = $attrs; qualities = $qualities }
    }
}
Log "Itemgenerierung: $($ConfigByLink.Count) Konfigurationen"

# Waffenwerte einer Item-Datei: myWeapon <..> : Elternwaffe { Overrides wie myDamageMax }
function Get-WeaponRef([string]$Text) {
    $m = [regex]::Match($Text, '(?m)^(\t*)myWeapon <[^>]*> (?:: |= )(\S+)(?: [0-9A-F]{32})?[ \t]*\r?$')
    if (-not $m.Success) { return $null }
    $indent = $m.Groups[1].Value
    $props = @{}
    $block = [regex]::Match($Text.Substring($m.Index + $m.Length), "^\r?\n$indent\{(.*?)\r?\n$indent\}", 'Singleline')
    if ($block.Success) {
        foreach ($p in [regex]::Matches($block.Groups[1].Value, "(?m)^$indent\t(my\w+) ([-0-9.]+)[ \t]*\r?$")) { $props[$p.Groups[1].Value] = [double]::Parse($p.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture) }
    }
    return @{ parent = $m.Groups[2].Value; props = $props }
}

# Items: nur Dateien mit eigener Generierungs-Konfiguration (keine Optik-, Kleidungs- oder MTX-Items)
$Items = @{}
$ItemHeads = @{}   # alle Items und Vorlagen: Elternvorlage und Anzeigename (fuer den Namen der Basiswaffe)
# Aeltere Items (z. B. Launch-Exotics) liegen im Division-1-Ordner "rogue"; Division 2 ("hunter") ueberschreibt gleichnamige
$itemFiles = @(Get-ChildItem (Join-Path $R 'juice\item') -Filter *.mitem) + @(Get-ChildItem (Join-Path $H 'juice\item') -Filter *.mitem)
foreach ($file in $itemFiles) {
    if ($file.Name -match '^(appearance_|player_gear_mtx|player_(shirt|pants|shoes|mask_mtx|patchitem)|ci_|blueprint_)') { continue }
    $text = [IO.File]::ReadAllText($file.FullName)
    $head = if ($text -match '(?m)^(\w+Item) (\S+) <[^>]*>(?: : (\S+))?') { @{ cls = $Matches[1]; id = $Matches[2]; template = $Matches[3] } } else { $null }
    if (-not $head) { continue }
    $ui = if ($text -match '(?m)^\s*myUIName (".*")\s*$') { Get-Loc $Matches[1].Trim('"') } else { $null }
    $weapon = if ($head.cls -eq 'WeaponItem') { Get-WeaponRef $text } else { $null }
    $ItemHeads[$head.id] = @{ id = $head.id; parent = $head.template; name = $ui; weapon = $weapon }
    if ($text -notmatch 'myItemGenerationConfig <[^>]*> = (\S+)') { continue }
    $link = $Matches[1]
    $tags = @([regex]::Matches($text, '(?m)^\s*ItemTag .* (\S+)\s*$') | ForEach-Object { $_.Groups[1].Value })
    $Items[$head.id] = @{ id = $head.id; cls = $head.cls; template = $head.template; link = $link; name = $ui; tags = $tags; weapon = $weapon; file = $file.Name }
}
Log "Items mit Konfiguration: $($Items.Count)"

function Get-ItemName($Item) {
    if (-not $Item -or -not $Item.name) { return $null }
    return Clean-Name $Item.name
}

$SlotNames = @{
    Mask = @{ de = 'Maske'; en = 'Mask' }; Chest = @{ de = 'Weste'; en = 'Chest' }; Backpack = @{ de = 'Rucksack'; en = 'Backpack' }
    Gloves = @{ de = 'Handschuhe'; en = 'Gloves' }; Holster = @{ de = 'Holster'; en = 'Holster' }; Kneepads = @{ de = 'Knieschoner'; en = 'Kneepads' }
}
function Get-SlotKey([string]$Text) {
    switch -regex ($Text) {
        'mask' { 'Mask'; break } 'chest' { 'Chest'; break } 'back' { 'Backpack'; break }
        'glove' { 'Gloves'; break } 'holster' { 'Holster'; break } 'knee' { 'Kneepads'; break }
        default { $null }
    }
}

# ---------- Alte Community-Daten (nur fuer: seit wann, Bezugsquelle, Attributwerte, Icons) ----------
# Vergleichsschluessel ohne Akzente, Satzzeichen und Gross/Klein (Pícaro's -> picaros)
function Get-Key([string]$Text) {
    if (-not $Text) { return '' }
    $plain = -join ($Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
    return ($plain -replace '[^A-Za-z0-9]', '').ToLower()
}
$Community = @{}
foreach ($f in 'gearsets', 'brandsets', 'exotics') {
    $p = Join-Path $Repo "data\community\$f.json"
    if (-not (Test-Path $p)) { $p = Join-Path $Repo "data\$f.json" }
    if (-not (Test-Path $p)) { continue }
    $json = [IO.File]::ReadAllText($p) | ConvertFrom-Json
    foreach ($e in $json) {
        $key = if ($e.name -is [string]) { $e.name } else { $e.name.en }
        $Community[(Get-Key $key)] = $e
    }
}
function Get-Old($Name) { if (-not $Name) { return $null }; return $Community[(Get-Key $Name.en)] }
function Get-Slug([string]$Text) { $Text = -join ($Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' }); return (($Text.ToLower() -replace "['’]", '' -replace '[^a-z0-9]+', '-').Trim('-')) }

# ---------- Gear-Sets und Brand-Sets ----------
$gearsets = New-Object System.Collections.Generic.List[object]
$brandsets = New-Object System.Collections.Generic.List[object]
foreach ($file in Get-ChildItem (Join-Path $H 'juice\item') -Filter *.mgearset) {
    $root = Read-Juice $file.FullName
    $gs = $root.kids | Where-Object { $_.kw -eq 'GearSet' } | Select-Object -First 1
    if (-not $gs) { continue }
    $name = Get-Loc (Get-Prop $gs 'myUIName')
    if (-not $name) { continue }
    $name = [ordered]@{ de = (Clean-Text $name.de).Trim(); en = (Clean-Text $name.en).Trim() }
    if ($name.en -notmatch '[A-Za-z]') { continue }

    $pieces = New-Object System.Collections.Generic.List[object]
    $itemsNode = Get-Kid $gs 'myItems'
    if ($itemsNode) {
        foreach ($line in $itemsNode.props) {
            if ($line -match '^Item ("([^"]+)"|(\S+))') { $label = if ($Matches[2]) { $Matches[2] } else { $Matches[3] }; $ref = Get-Ref $line; if ($ref) { $pieces.Add(@{ label = $label; id = $ref.name }) } }
        }
    }

    $bonuses = New-Object System.Collections.Generic.List[object]
    $talents = New-Object System.Collections.Generic.List[object]
    $unlocks = Get-Kid $gs 'myUnlocks'
    if ($unlocks) {
        foreach ($u in $unlocks.kids) {
            $count = [int](Get-Prop $u 'myRequiredNumberOfItems')
            $pvpEffects = $null
            $ovs = Get-Kid $u 'myEffectsOverrides'
            if ($ovs) { foreach ($o in $ovs.kids) { if ($o.name -match 'PvP') { $pvpEffects = Read-BonusList (Get-Kid $o 'myEffects') } } }
            $effects = Get-Kid $u 'myEffects'
            if (-not $effects) { continue }
            foreach ($b in Read-BonusList $effects) {
                if (-not $b.attr -or $null -eq $b.value) { continue }
                $pvp = $null
                if ($pvpEffects) { $hit = $pvpEffects | Where-Object { $_.uid -eq $b.uid } | Select-Object -First 1; if ($hit) { $pvp = Get-BonusValue $hit.attr $hit.value } }
                $bonuses.Add([ordered]@{ pieces = $count; attr = $b.attr; label = Get-AttrLabel $b.attr; pve = Get-BonusValue $b.attr $b.value; pvp = $pvp; scales = Get-Scales @($b.attr) $null })
            }
            foreach ($line in $effects.props) {
                if ($line -match '^Talent ') { $ref = Get-Ref $line; $t = if ($ref) { Get-Talent $ref.name } else { $null }; if ($t) { $talents.Add((With-Slot "$($count)pc" $t)) } }
            }
        }
    }

    $isGearset = $talents.Count -gt 0
    # Nicht jedes Named Item steht in myItems; ueber das Markenkuerzel der Item-ID (player_gear_back_511_01_named) zuordnen
    $brandKeys = @($pieces | ForEach-Object { if ($_.id -match '^player_gear_(?:mask|chest|back|gloves|holster|kneepads)_([a-z0-9]+)_\d+$') { $Matches[1] } } | Select-Object -Unique)
    foreach ($key in $brandKeys) {
        foreach ($id in $Items.Keys | Where-Object { $_ -match "^player_gear_(mask|chest|back|gloves|holster|kneepads)_$($key)_\d+_named" } | Sort-Object) {
            if (-not ($pieces | Where-Object { $_.id -eq $id })) { $pieces.Add(@{ label = "Named $($Matches[1])"; id = $id }) }
        }
    }
    # Chest-/Rucksack-Talente der Gear-Sets und Talente/Attribute der Named Items kommen aus den Itemgenerierungs-Konfigurationen
    $named = New-Object System.Collections.Generic.List[object]
    $seenNamed = @{}
    $oldSet = Get-Old $name
    foreach ($p in $pieces) {
        $item = $Items[$p.id]
        if (-not $item) { continue }
        $cfg = $ConfigByLink[$item.link]
        if ($p.label -match 'Named') {
            $nm = Get-ItemName $item
            if (-not $nm -or $nm.en -notmatch '[A-Za-z]' -or $seenNamed.ContainsKey($nm.en)) { continue }
            $seenNamed[$nm.en] = $true
            $slot = Get-SlotKey ("$($p.label) $($item.id)".ToLower())
            $nt = $null; $na = $null
            if ($cfg) {
                $tid = $cfg.talents | Select-Object -First 1
                if ($tid) { $nt = Get-Talent $tid.id }
                $core = $cfg.attrs | Where-Object { -not $_.core } | Select-Object -First 1
                if (-not $nt -and $core) { $na = [ordered]@{ attr = $core.attr; label = Get-AttrLabel $core.attr; value = $null; unit = $null; scales = Get-Scales @($core.attr) $null } }
            }
            # Werte verbesserter Named-Attribute stehen nur als Kurven in den Daten; Zahl aus den Community-Daten uebernehmen
            $oldNamed = if ($oldSet) { $oldSet.namedItems | Where-Object { (Get-Key $_.name) -eq (Get-Key $nm.en) } | Select-Object -First 1 } else { $null }
            if ($oldNamed -and $oldNamed.attribute) {
                if (-not $na -and -not $nt) { $na = [ordered]@{ attr = $null; label = [ordered]@{ de = $oldNamed.attribute.stat; en = $oldNamed.attribute.stat }; value = $null; unit = $null; scales = @() } }
                if ($na) { $na.value = $oldNamed.attribute.value; $na.unit = $oldNamed.attribute.unit }
            }
            $named.Add([ordered]@{ name = $nm; slot = $slot; slotLabel = $(if ($slot) { $SlotNames[$slot] } else { $null }); talent = $nt; attribute = $na })
        } elseif ($isGearset -and $cfg) {
            $slot = Get-SlotKey ("$($p.label) $($item.id)".ToLower())
            foreach ($ct in $cfg.talents) {
                if ($talents | Where-Object { $_.id -eq $ct.id }) { continue }
                $t = Get-Talent $ct.id
                if ($t) { $talents.Add((With-Slot $(if ($slot -eq 'Backpack') { 'backpack' } else { 'chest' }) $t)) }
            }
        }
    }
    if ($bonuses.Count -eq 0 -and $talents.Count -eq 0) { continue }

    $old = Get-Old $name
    $entry = [ordered]@{
        id = Get-Slug $name.en
        kind = $(if ($isGearset) { 'gearset' } else { 'brandset' })
        name = $name
        added = $(if ($old) { $old.added } else { $null })
        bonuses = $bonuses.ToArray()
        talents = $talents.ToArray()
        namedItems = $named.ToArray()
        source = "juice\item\$($file.Name)"
    }
    if ($isGearset) { $gearsets.Add($entry) } else { $brandsets.Add($entry) }
}
Log "Gear-Sets: $($gearsets.Count), Brand-Sets: $($brandsets.Count)"

# ---------- Exotics ----------
$Categories = @{
    'Assault Rifle' = @{ de = 'Sturmgewehr'; en = 'Assault Rifle' }; 'LMG' = @{ de = 'LMG'; en = 'LMG' }
    'Marksman Rifle' = @{ de = 'Präzisionsgewehr'; en = 'Marksman Rifle' }; 'Rifle' = @{ de = 'Gewehr'; en = 'Rifle' }
    'SMG' = @{ de = 'MP'; en = 'SMG' }; 'Shotgun' = @{ de = 'Schrotflinte'; en = 'Shotgun' }; 'Pistol' = @{ de = 'Pistole'; en = 'Pistol' }
}
function Get-WeaponCategory([string]$Text) {
    switch -regex ($Text) {
        'assault_?rifle|_ar_' { 'Assault Rifle'; break } 'light_?machine_?gun|lmg' { 'LMG'; break }
        'marksm[ae]n|sniper|_mmr|dmr' { 'Marksman Rifle'; break } 'sub_?machine|smg' { 'SMG'; break }
        'shotgun' { 'Shotgun'; break } 'pistol|revolver|handgun' { 'Pistol'; break } 'rifle' { 'Rifle'; break }
        default { $null }
    }
}

# Spiel-Attribut -> Statname in den Community-Daten (fuer die Uebernahme der Hoechstwerte)
$CommunityStat = [ordered]@{
    'TargetOutOfCover' = 'Damage to Targets out of Cover'; 'WeaponDamageMultiplierHealth' = 'Damage to Health'
    'DamageDoneToArmor' = 'Damage to Armor'; '^ArmorGearFlatBonus' = 'Total Armor'; 'ArmorRegen' = 'Armor Regeneration'
    'CriticalHitDamage' = 'Critical Hit Damage'; 'CriticalHitChance' = 'Critical Hit Chance'; 'WeaponDamageMultiplierHead' = 'Headshot Damage'
    '^SkillPower' = 'Skill Tier'
}
# Saison-Tag (z. B. Y8S3_Exotic_03) als Ersatz, wenn die Community-Daten das Item nicht kennen
function Get-AddedFromTags($Tags) {
    foreach ($t in $Tags) { if ($t -match '^Y(\d+)S(\d+)') { return [ordered]@{ date = $null; update = "Year $($Matches[1]) Season $($Matches[2])"; label = "Y$($Matches[1])S$($Matches[2])" } } }
    return $null
}

$exotics = New-Object System.Collections.Generic.List[object]
$seenExotic = @{}
foreach ($item in $Items.Values | Sort-Object { $_.id }) {
    if ($item.tags -notcontains 'Exotic') { continue }
    $cfg = $ConfigByLink[$item.link]
    if (-not $cfg -or $cfg.talents.Count -eq 0) { continue }
    $name = Get-ItemName $item
    if (-not $name -or $seenExotic.ContainsKey($name.en)) { continue }
    $seenExotic[$name.en] = $true

    $category = if ($item.cls -eq 'WeaponItem') { Get-WeaponCategory "$($item.id) $($item.template)" } else { Get-SlotKey $item.id }
    # Aktiv sind nur die Talente, die die Itemgenerierung tatsaechlich verknuepft (myPresetTalent)
    $talents = New-Object System.Collections.Generic.List[object]
    foreach ($ct in $cfg.talents) {
        if ($talents | Where-Object { $_.id -eq $ct.id }) { continue }
        $t = Get-Talent $ct.id
        if ($t -and $t.name) { $talents.Add((With-Slot $(if ($ct.id -match 'holster') { 'holstered' } else { 'exotic' }) $t)) }
    }
    if ($talents.Count -eq 0) { continue }
    # Gleichnamige Nachbar-Talente (z. B. talent_exotic_lmg_mk1_b/_holstered) ohne Verknuepfung: Altlasten frueherer Versionen
    $legacy = New-Object System.Collections.Generic.List[object]
    foreach ($ct in $cfg.talents) {
        $base = $ct.id -replace '_(a|b|c)$', ''
        foreach ($sfx in '_a', '_b', '_c', '_holstered') {
            $sib = "$base$sfx"
            if ($sib -eq $ct.id -or ($talents | Where-Object { $_.id -eq $sib }) -or ($legacy | Where-Object { $_.id -eq $sib })) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $TalentDir "$sib.mtalent"))) { continue }
            $t = Get-Talent $sib
            if ($t -and $t.name) { $legacy.Add((With-Slot $(if ($sib -match 'holster') { 'holstered' } else { 'exotic' }) $t)) }
        }
    }

    $old = Get-Old $name
    # Feste Exotic-Attribute: welches Attribut kommt aus dem Spiel, die Hoechstwerte (nur als Kurven hinterlegt) aus den Community-Daten
    $seenAttr = @{}
    $attributes = foreach ($a in $cfg.attrs) {
        if ($seenAttr.ContainsKey($a.attr)) { continue }
        $seenAttr[$a.attr] = $true
        $label = Get-AttrLabel $a.attr
        $stat = $label.en
        foreach ($k in $CommunityStat.Keys) { if ($a.attr -match $k) { $stat = $CommunityStat[$k]; break } }
        $value = $null; $unit = $null
        if ($old -and $old.attributes) {
            $match = $old.attributes | Where-Object { $_.stat -and $stat -and $_.stat.ToLower() -eq $stat.ToLower() } | Select-Object -First 1
            if ($match) { $value = $match.value; $unit = $match.unit }
        }
        [ordered]@{ attr = $a.attr; label = $label; value = $value; unit = $unit; core = $a.core; scales = Get-Scales @($a.attr) $null }
    }
    $obtainTags = @($item.tags | Where-Object { $_ -match 'Raid|DZ|Drop|Curated|Mission|Vendor|Crafting|Blueprint|Season|Y\dS\d|Event|Cache|Boss' })
    $exotics.Add([ordered]@{
        id = Get-Slug $name.en
        kind = 'exotic'
        category = $category
        categoryLabel = $(if (-not $category) { $null } elseif ($item.cls -eq 'WeaponItem') { $Categories[$category] } else { $SlotNames[$category] })
        isWeapon = ($item.cls -eq 'WeaponItem')
        name = $name
        added = $(if ($old) { $old.added } else { Get-AddedFromTags $item.tags })
        talents = $talents.ToArray()
        legacyTalents = $legacy.ToArray()
        attributes = @($attributes)
        obtain = $(if ($old -and $old.obtain) { $old.obtain } else { $null })
        tags = $obtainTags
        source = "juice\item\$($item.file)"
    })
}
Log "Exotics: $($exotics.Count)"

# ---------- Named Weapons ----------
# Waffen-Definitionen (rogue\juice\weapon): Elternwaffe und eigene Werte; fehlende Werte erbt eine Waffe von ihren Eltern
$WeaponDefs = @{}
foreach ($file in Get-ChildItem (Join-Path $R 'juice\weapon') -Filter *.mweapon) {
    $txt = [IO.File]::ReadAllText($file.FullName)
    if ($txt -notmatch '(?m)^Weapon (\S+) <[^>]*>(?: : (\S+))?') { continue }
    $name = $Matches[1]; $parent = $Matches[2]
    $props = @{}
    foreach ($p in [regex]::Matches($txt, '(?m)^\t(my\w+) ([-0-9.]+)[ \t]*\r?$')) { if (-not $props.ContainsKey($p.Groups[1].Value)) { $props[$p.Groups[1].Value] = [double]::Parse($p.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture) } }
    $WeaponDefs[$name] = @{ parent = $parent; props = $props }
}
function Get-WeaponStat($Ref, [string]$Key) {
    if (-not $Ref) { return $null }
    if ($Ref.props.ContainsKey($Key)) { return $Ref.props[$Key] }
    $name = $Ref.parent; $depth = 0
    while ($name -and $WeaponDefs[$name] -and $depth -lt 20) {
        if ($WeaponDefs[$name].props.ContainsKey($Key)) { return $WeaponDefs[$name].props[$Key] }
        $name = $WeaponDefs[$name].parent; $depth++
    }
    return $null
}
# Normale Version derselben Waffe: gleiche Item-ID ohne _named..., sonst eine andere Stufe (_t1_v1 ...)
# Sie liegt oft nur im rogue-Ordner und hat keine eigene Generierungs-Konfiguration, deshalb ueber $ItemHeads
function Get-BaseWeaponItem($Item) {
    $id = $Item.id -replace '_named.*$|_intro$', ''
    foreach ($c in $id, ($id -replace '_v\d+$', ''), ($id -replace '_t\d+(_v\d+)?$', '_t1_v1'), ($id -replace '_t\d+(_v\d+)?$', '_t2_v1'), ($id -replace '_t\d+(_v\d+)?$', '_t3_v1')) {
        if ($c -ne $Item.id -and $ItemHeads[$c] -and $ItemHeads[$c].name -and (Get-ItemWeapon $ItemHeads[$c])) { return $ItemHeads[$c] }
    }
    return $null
}
# Waffe eines Items; ohne eigenes myWeapon erbt es die Waffe des Eltern-Items (z. B. Scalpel, Sleipnir)
function Get-ItemWeapon($Item) {
    $node = $Item; $depth = 0
    while ($node -and $depth -lt 10) { if ($node.weapon) { return $node.weapon }; $node = if ($node.template) { $ItemHeads[$node.template] } else { $ItemHeads[$node.parent] }; $depth++ }
    return $null
}
# Anzeigename aus der Vorlagenkette (z. B. SIG 556), falls es keine normale Version gibt
function Get-TemplateName([string]$Id) {
    $depth = 0
    while ($Id -and $ItemHeads[$Id] -and $depth -lt 10) { if ($ItemHeads[$Id].name) { return $ItemHeads[$Id].name }; $Id = $ItemHeads[$Id].parent; $depth++ }
    return $null
}

$namedWeapons = New-Object System.Collections.Generic.List[object]
$seenNamedWeapon = @{}
# Kuerzeste ID zuerst: die Grundvariante gewinnt vor _vendor_roaming, _hunter_box usw.
foreach ($item in $Items.Values | Where-Object { $_.cls -eq 'WeaponItem' -and $_.tags -notcontains 'Exotic' } | Sort-Object { $_.id.Length }, { $_.id }) {
    $cfg = $ConfigByLink[$item.link]
    if (-not $cfg) { continue }
    $nt = $cfg.talents | Where-Object { $_.named } | Select-Object -First 1
    if (-not $nt) { continue }
    $name = Get-ItemName $item
    if (-not $name -or $name.en -notmatch '[A-Za-z]') { continue }
    if ($seenNamedWeapon.ContainsKey($name.en)) { $seenNamedWeapon[$name.en].variants += $item.id; continue }
    $talent = Get-Talent $nt.id
    if (-not $talent -or -not $talent.name) { continue }

    $category = Get-WeaponCategory "$($item.id) $($item.template)"
    $baseItem = Get-BaseWeaponItem $item
    $baseName = if ($baseItem) { Get-ItemName $baseItem } else { $t = Get-TemplateName $item.template; if ($t) { Clean-Name $t } else { $null } }
    # Grundschaden der Datei (myDamageMax); Ingame-Schaden = dieser Wert x Kurven (siehe PhysicalDamageMaxFinal)
    $wref = Get-ItemWeapon $item
    $dmg = Get-WeaponStat $wref 'myDamageMax'
    $baseDmg = if ($baseItem) { Get-WeaponStat (Get-ItemWeapon $baseItem) 'myDamageMax' } else { $null }
    $reload = Get-WeaponStat $wref 'myReloadTimeMS'
    if (-not $dmg) { $dmg = $null }   # Event-Waffen ohne Schaden (z. B. Wasserpistole)
    $stats = [ordered]@{
        damage = $(if ($dmg) { [math]::Round($dmg, 2) } else { $null })
        baseDamage = $(if ($baseDmg) { [math]::Round($baseDmg, 2) } else { $null })
        damageDiff = $(if ($dmg -and $baseDmg -and [math]::Abs($dmg - $baseDmg) -gt 0.01) { [math]::Round(($dmg / $baseDmg - 1) * 100, 1) } else { $null })
        rpm = Get-WeaponStat $wref 'myRPM'
        magazine = Get-WeaponStat $wref 'myClipSize'
        reload = $(if ($reload) { [math]::Round($reload / 1000, 2) } else { $null })
        headshot = $(if ($v = Get-WeaponStat $wref 'myDamageMultiplierHead') { [math]::Round($v, 2) } else { $null })
        range = $(if ($v = Get-WeaponStat $wref 'myRangeOptimal') { [math]::Round($v, 1) } else { $null })
    }
    $entry = [ordered]@{
        id = Get-Slug $name.en
        kind = 'namedweapon'
        category = $category
        categoryLabel = $(if ($category) { $Categories[$category] } else { $null })
        isWeapon = $true
        name = $name
        base = $baseName
        added = $null
        talents = @((With-Slot 'named' $talent))
        stats = $stats
        tags = @($item.tags | Where-Object { $_ -match 'DZ|Raid|Vendor|Season|Event|Hunter|Box' })
        variants = @()
        source = "juice\item\$($item.file)"
    }
    $seenNamedWeapon[$name.en] = $entry
    $namedWeapons.Add($entry)
}
foreach ($w in $namedWeapons) { $w.variants = @($w.variants) }
Log "Named Weapons: $($namedWeapons.Count)"

# ---------- Talente: wo jedes Talent vorkommt ----------
# Wuerfelbare Talente stehen in Talentlisten; nur Listen, die aktuelle Item-Konfigurationen benutzen, zaehlen
$AllWeapons = @('Assault Rifle', 'LMG', 'Marksman Rifle', 'Rifle', 'SMG', 'Shotgun', 'Pistol')
function Get-ListSlots([string]$List) {
    switch -regex ($List) {
        'chest' { return @('Chest') } 'back' { return @('Backpack') }
        '^advanced_weapon' { return $AllWeapons } '^Assault' { return @('Assault Rifle') } '^LMG$' { return @('LMG') }
        '^MMR$' { return @('Marksman Rifle') } '^Pistol$' { return @('Pistol') } '^Rifle$' { return @('Rifle') }
        '^Shotgun$|shotgun_cycling' { return @('Shotgun') } '^SMG$' { return @('SMG') } 'Prototype' { return @('Prototype') }
    }
    return @()
}
$TalentIndex = [ordered]@{}
function Add-TalentOrigin([string]$Id, [string]$Source, [string[]]$Slots, $Origin) {
    if (-not $TalentIndex.Contains($Id)) {
        $t = Get-Talent $Id
        if (-not $t -or -not $t.name -or -not $t.text) { return }
        $TalentIndex[$Id] = [ordered]@{ talent = $t; sources = New-Object System.Collections.Generic.List[string]; slots = New-Object System.Collections.Generic.List[string]; origins = New-Object System.Collections.Generic.List[object] }
    }
    $e = $TalentIndex[$Id]
    if (-not $e.sources.Contains($Source)) { $e.sources.Add($Source) }
    foreach ($s in $Slots) { if ($s -and -not $e.slots.Contains($s)) { $e.slots.Add($s) } }
    if ($Origin) { $e.origins.Add($Origin) }
}

$listFile = Join-Path $H "juice\itemgeneration\talentlists\talentlist_code1_data$Version.mitemgenerationtalentlists"
$listRoot = Read-Juice $listFile
# Nur Talente gelber (High-End-)Items: wuerfelbare Talente und Named-Talente der Brand-Sets.
# Gear-Set-, Exotic- und Prototyp-Talente (Augments) gehoeren zu genau einem Item und stehen im Codex.
foreach ($list in $listRoot.kids | Where-Object { $_.kw -eq 'TalentListContainer' }) {
    if (-not $UsedTalentLists.ContainsKey($list.name) -or $list.name -match 'Prototype') { continue }
    $slots = Get-ListSlots $list.name
    foreach ($tl in Find-Kids $list 'myTalents') { foreach ($line in $tl.props) { $ref = Get-Ref $line; if ($ref) { Add-TalentOrigin $ref.name 'roll' $slots $null } } }
}
foreach ($set in $brandsets) {
    foreach ($n in $set.namedItems) {
        if ($n.talent) { Add-TalentOrigin $n.talent.id 'named' @($n.slot) ([ordered]@{ kind = 'named'; item = $n.name; set = $set.name; slot = $n.slot }) }
    }
}
# Named Weapons: Basiswaffe statt Marke in Klammern
foreach ($w in $namedWeapons) {
    Add-TalentOrigin $w.talents[0].id 'named' @($w.category) ([ordered]@{ kind = 'named'; item = $w.name; set = $w.base; slot = $w.category })
}

$talents = New-Object System.Collections.Generic.List[object]
foreach ($id in $TalentIndex.Keys) {
    $e = $TalentIndex[$id]
    $out = [ordered]@{}
    foreach ($k in $e.talent.Keys) { $out[$k] = $e.talent[$k] }
    $out['sources'] = $e.sources.ToArray()
    $out['slots'] = $e.slots.ToArray()
    $out['origins'] = $e.origins.ToArray()
    # Perfekte Named-Version (talent_x_perfect) und Grundtalent (talent_x) gegenseitig verlinken
    $base = $id -replace '_perfect$', ''
    $out['perfectOf'] = $(if ($base -ne $id -and $TalentIndex.Contains($base)) { $base } else { $null })
    $out['perfect'] = $(if ($TalentIndex.Contains("$($id)_perfect")) { "$($id)_perfect" } else { $null })
    $talents.Add($out)
}
Log "Talente: $($talents.Count) (wuerfelbar: $(@($talents | Where-Object { $_.sources -contains 'roll' }).Count))"

# ---------- Schaden ueber Zeit (Brennen, Bluten, Gift): Grundwerte, Formeln, Skill-Tier-Boni ----------
# Formel einer Quelle in Faktoren zerlegen: Grundwert x Level-Kurve x (1 + a + b) x (1 + c) ...
function Split-Top([string]$Text, [char]$Op) {
    $parts = New-Object System.Collections.Generic.List[string]; $depth = 0; $start = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq '(') { $depth++ } elseif ($c -eq ')') { $depth-- } elseif ($c -eq $Op -and $depth -eq 0) { $parts.Add($Text.Substring($start, $i - $start)); $start = $i + 1 }
    }
    $parts.Add($Text.Substring($start)); return $parts.ToArray()
}
function Unwrap([string]$Text) {
    while ($Text.StartsWith('(') -and $Text.EndsWith(')')) {
        $depth = 0; $closesAtEnd = $true
        for ($i = 0; $i -lt $Text.Length - 1; $i++) { if ($Text[$i] -eq '(') { $depth++ } elseif ($Text[$i] -eq ')') { $depth--; if ($depth -eq 0) { $closesAtEnd = $false; break } } }
        if (-not $closesAtEnd) { break }
        $Text = $Text.Substring(1, $Text.Length - 2)
    }
    return $Text
}
function Get-Factors([string]$Formula, $Acc) {
    $f = Unwrap (($Formula -replace '\s', '') -replace '\*-1$', '')
    $sum = @(Split-Top $f '+')
    if ($sum.Count -gt 1 -and $sum[0].Contains('*')) { $f = Unwrap $sum[0] }   # angehaengte Flat-Boni ignorieren
    foreach ($term in @(Split-Top $f '*')) {
        $u = Unwrap $term
        if (@(Split-Top $u '*').Count -gt 1) { [void](Get-Factors $u $Acc); continue }
        if ($u -match '^1\+') {
            $attrs = @((Split-Top $u '+') | Where-Object { $_ -ne '1' })
            # Sammel-Bonus wie turret_assault_damage_modBonus_Final = (1 + a) * (1 + b) - 1 in seine Klammern aufloesen
            $composite = if ($attrs.Count -eq 1 -and $AttrByName[$attrs[0]]) { $AttrByName[$attrs[0]].formula } else { $null }
            if ($composite -and ($composite -replace '\s', '') -match '^(.+)-1$') { [void](Get-Factors $Matches[1] $Acc); continue }
            $Acc.brackets.Add($attrs); continue
        }
        if ($u -match '^[0-9.]+$') { $Acc.base = [double]$u; continue }
        if ($u -match '_Base$' -and $AttrByName[$u]) { $Acc.base = [double]($AttrByName[$u].formula); continue }
    }
    return $Acc
}
# Skill-Tier-Tabelle: Boni je Tier (0..7) fuer die Attribute, die in der Formel vorkommen
function Get-TierTable([string]$File, [string[]]$Wanted) {
    $table = @{}
    $files = @($File)
    $txt = [IO.File]::ReadAllText((Join-Path $H "juice\item\$File.mskilltier"))
    if ($txt -match '(?m)^SkillTier \S+ <[^>]*> : (\S+)') { $files += $Matches[1].ToLower() }
    foreach ($f in $files) {
        $path = Join-Path $H "juice\item\$f.mskilltier"
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $tier = (Read-Juice $path).kids | Where-Object { $_.kw -eq 'SkillTier' } | Select-Object -First 1
        $unlocks = Get-Kid $tier 'myUnlocks'
        if (-not $unlocks) { continue }
        foreach ($u in $unlocks.kids) {
            $level = [int](Get-Prop $u 'myRequiredAttributeValue')
            foreach ($b in Read-BonusList (Get-Kid $u 'myEffects')) {
                if ($Wanted -notcontains $b.attr -or $null -eq $b.value) { continue }
                if (-not $table.ContainsKey($b.attr)) { $table[$b.attr] = @(0, 0, 0, 0, 0, 0, 0, 0) }
                if ($f -eq $File -or $table[$b.attr][$level] -eq 0) { $table[$b.attr][$level] = $b.value }
            }
        }
    }
    return $table
}
function Get-TickSeconds([string]$Rule) {
    $root = Read-Juice (Join-Path $H "juice\talentrules\$Rule.mtalentrules")
    $npc = Find-Kids $root 'TalentRule' | Where-Object { $_.name -match 'NPC' } | Select-Object -First 1
    $act = if ($npc) { Find-Kids $npc 'ApplyDamageOrHealing' | Select-Object -First 1 } else { $null }
    if ($act) { return [double](Get-Prop $act 'myFrequency') } else { return $null }
}
# Standard-Statuseffekte (gegen Gegner) plus alle Skill-Schadensformeln aus player_skill_dictionary
$DotDefs = @(
    @{ id = 'burn-status'; effect = 'Burn'; kind = 'status'; attr = 'NPC_Burn_Damage_Base'; rule = 'statuseffecttalentrule_burn'; label = @{ de = 'Statuseffekt Brennen'; en = 'Burn status effect' }; note = @{ de = 'Ember Engine, Fafnir, Brandmunition, Talente, Exotics'; en = 'Ember Engine, Fafnir, incendiary ammo, talents, exotics' } }
    @{ id = 'bleed-status'; effect = 'Bleed'; kind = 'status'; attr = 'NPC_Bleed_Damage_Base'; rule = 'statuseffecttalentrule_bleed'; label = @{ de = 'Statuseffekt Bluten'; en = 'Bleed status effect' }; note = @{ de = 'Explosiv- und Hohlspitzmunition, Talente, Exotics'; en = 'Explosive and hollow-point ammo, talents, exotics' } }
    @{ id = 'poison-status'; effect = 'Poison'; kind = 'status'; attr = 'NPC_Poison_Damage_Base'; rule = 'statuseffecttalentrule_poison'; label = @{ de = 'Statuseffekt Gift'; en = 'Poison status effect' }; note = @{ de = 'Talente, Exotics'; en = 'talents, exotics' } }
)
# Skill-Tier-Dateien: welche Attribute sie veraendern, Skillname (Familie aus der Tier-Tabelle, Variante aus dem Skill-Mod-Item)
$TierFiles = @{}
foreach ($tf in Get-ChildItem (Join-Path $H 'juice\item') -Filter 'skill_tier_*.mskilltier') {
    $txt = [IO.File]::ReadAllText($tf.FullName)
    $attrs = @([regex]::Matches($txt, 'myAttributeUID ([0-9A-F]{32})') | ForEach-Object { $Attr[$_.Groups[1].Value].name } | Where-Object { $_ } | Select-Object -Unique)
    $family = if ($txt -match 'myUIName "([^\r\n]*)"') { Get-Loc $Matches[1] } else { $null }
    $variant = $null
    if ($txt -match 'mySkillMod <[^>]*> = (\S+)') {
        $mod = $Matches[1]
        $itemPath = @((Join-Path $H "juice\item\$mod.mitem"), (Join-Path $R "juice\item\$mod.mitem")) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($itemPath -and ([IO.File]::ReadAllText($itemPath) -match '(?m)^\s*myUIName (".*")\s*$')) { $variant = Clean-Name (Get-Loc $Matches[1].Trim('"')) }
    }
    if ($family) {
        $family = [ordered]@{ de = ($family.de -replace '-?(Fertigkeitenr(ä|a)nge?|Fertigkeitenrang|R(ä|a)nge|Skalierung)$', '').Trim(); en = ($family.en -replace ' ?(Skill Tiers?|Tiers|Scaling)$', '').Trim() }
    }
    $TierFiles[$tf.BaseName] = @{ attrs = $attrs; family = $family; variant = $variant; isBase = ($tf.BaseName -match '_base$') }
}
$Generic = '^(allskills_damage_mod_Bonus|GearTalentAllSkillsDamageModBonus|BlastDamageModBonus|BurnDamageModBonus|BleedDamageModBonus)$'
# Skill-Familien (die Tier-Tabellen benennen sie uneinheitlich) und welche Tier-Datei zu welcher Schadensformel gehoert;
# der Variantenname (z. B. "Feuerteufel") kommt aus dem Skill-Mod-Item der Tier-Datei
$SkillFamilies = @{
    turret = @{ de = 'Geschütz'; en = 'Turret' }; drone = @{ de = 'Drohne'; en = 'Drone' }; seeker = @{ de = 'Suchermine'; en = 'Seeker Mine' }
    sticky = @{ de = 'Haftgranate'; en = 'Sticky Bomb' }; chem = @{ de = 'Chem-Werfer'; en = 'Chem Launcher' }; hive = @{ de = 'Drohnenstock'; en = 'Hive' }
    trap = @{ de = 'Falle'; en = 'Trap' }; firefly = @{ de = 'Glühwürmchen'; en = 'Firefly' }; pulse = @{ de = 'Impulsgeber'; en = 'Pulse' }
}
$Explosion = @{ de = 'Explosion'; en = 'explosion' }
$SkillMap = [ordered]@{
    '^turret2_assault' = @{ family = 'turret'; tier = 'skill_tier_turret_assault' }
    '^turret2_sniper' = @{ family = 'turret'; tier = 'skill_tier_turret_sniper' }
    '^turret2_flame' = @{ family = 'turret'; tier = 'skill_tier_turret_flamer'; part = @{ de = 'Flammenstrahl'; en = 'flame stream' } }
    '^turret2_mortar' = @{ family = 'turret'; tier = 'skill_tier_turret_mortar' }
    '^drone_assault' = @{ family = 'drone'; tier = 'skill_tier_drone_assault' }
    '^drone_bombardier' = @{ family = 'drone'; tier = 'skill_tier_drone_bombardier' }
    '^seekermine_airburst' = @{ family = 'seeker'; tier = 'skill_tier_seeker_airburst'; part = $Explosion }
    '^seekermine_cluster' = @{ family = 'seeker'; tier = 'skill_tier_seeker_cluster' }
    '^seekermine_explosive' = @{ family = 'seeker'; tier = 'skill_tier_seeker_explosive' }
    '^sticky_burn' = @{ family = 'sticky'; tier = 'skill_tier_sticky_burn'; part = $Explosion }
    '^sticky_explosive' = @{ family = 'sticky'; tier = 'skill_tier_sticky_explosive' }
    '^sticky_emp' = @{ family = 'sticky'; tier = 'skill_tier_sticky_emp' }
    '^chemlauncher_explosive' = @{ family = 'chem'; tier = 'skill_tier_chem_explosive'; part = $Explosion }
    '^chemlauncher_corrosive' = @{ family = 'chem'; tier = 'skill_tier_chem_corrosive'; part = @{ de = 'Wolke'; en = 'cloud' } }
    '^hive_hornets' = @{ family = 'hive'; tier = 'skill_tier_hive_stinger' }
    '^trap_explosive' = @{ family = 'trap'; tier = 'skill_tier_trap_shrapnel' }
    '^firefly_hardpoint' = @{ family = 'firefly'; tier = 'skill_tier_firefly_hardpoint' }
    '^firefly_magnetic' = @{ family = 'firefly'; tier = 'skill_tier_firefly_shrapnel' }
    '^pulse_emp' = @{ family = 'pulse'; tier = 'skill_tier_pulse_emp' }
}
# Feuerrate der Skills, die wie Waffen schiessen (Waffendaten in rogue\juice\weapon)
# (Scharfschuetzen-Geschuetz ausgelassen: feuert nur auf Befehl, 3 Schuss)
$SkillWeapons = @{ turret2_assault_damage_Final = 'npc_weapon_player_turret'; drone_assault_damage_Final = 'npc_weapon_player_drone' }
foreach ($def in $formulas | Where-Object { $_.dict -eq 'player_skill_dictionary' -and $_.name -match '(?i)damage_?final$' -and $_.name -notmatch '^pvp_|ricochet' -and $_.formula }) {
    $DotDefs += @{ id = $def.name.ToLower(); attr = $def.name; kind = 'skill' }
}
$dotSources = New-Object System.Collections.Generic.List[object]
foreach ($d in $DotDefs) {
    $def = $AttrByName[$d.attr]
    if (-not $def) { Log "Schadensquelle fehlt: $($d.attr)"; continue }
    $acc = Get-Factors $def.formula @{ base = $null; brackets = (New-Object System.Collections.Generic.List[object]) }
    if (-not $acc.base) { continue }
    $all = @($acc.brackets | ForEach-Object { $_ })
    $own = @($all | Where-Object { $_ -notmatch $Generic })
    $effect = $d.effect
    if (-not $effect) { $effect = if ($d.attr -match '(?i)bleed') { 'Bleed' } elseif ($d.attr -match '(?i)burn' -and $acc.base -le 200) { 'Burn' } else { 'Direct' } }
    $tiers = @{}; $label = $d.label; $family = $null
    if ($d.kind -eq 'skill') {
        $map = $null
        foreach ($k in $SkillMap.Keys) { if ($d.attr -match $k) { $map = $SkillMap[$k]; break } }
        if (-not $map) { Log "Skill ohne Zuordnung: $($d.attr)"; continue }
        $family = $map.family
        $tiers = Get-TierTable $map.tier $all
        $variant = $TierFiles[$map.tier].variant
        $fam = $SkillFamilies[$map.family]
        $label = [ordered]@{ de = "$($fam.de): $($variant.de)"; en = "$($fam.en): $($variant.en)" }
        $suffix = if ($effect -eq 'Burn') { @{ de = 'Brennen'; en = 'burn' } } elseif ($effect -eq 'Bleed') { @{ de = 'Bluten'; en = 'bleed' } } else { $map.part }
        if ($suffix) { $label = [ordered]@{ de = "$($label.de) ($($suffix.de))"; en = "$($label.en) ($($suffix.en))" } }
    }
    $rpm = $null
    if ($SkillWeapons[$d.attr]) {
        $wp = Join-Path $R "juice\weapon\$($SkillWeapons[$d.attr]).mweapon"
        if ((Test-Path -LiteralPath $wp) -and ([IO.File]::ReadAllText($wp) -match 'myRPM ([0-9.]+)')) { $rpm = [double]$Matches[1] }
    }
    $dotSources.Add([ordered]@{
        id = $d.id; effect = $effect; kind = $d.kind; family = $family; label = $label; note = $d.note
        attr = $d.attr; formula = $def.formula
        base = $acc.base
        brackets = @($acc.brackets | ForEach-Object { ,@($_) })
        tierBonus = $tiers
        tickSeconds = $(if ($d.rule) { Get-TickSeconds $d.rule } elseif ($effect -eq 'Burn') { Get-TickSeconds 'statuseffecttalentrule_burn' } elseif ($effect -eq 'Bleed') { Get-TickSeconds 'statuseffecttalentrule_bleed' } else { $null })
        rpm = $rpm
    })
}
$levelCurve40 = [math]::Round([math]::Pow(1.125, 29) * [math]::Pow(1.25, 5) * [math]::Pow(1.125, 10), 2)
Log "DoT-Quellen: $($dotSources.Count), Level-Kurve Stufe 40 = $levelCurve40"

# ---------- Ausgabe ----------
$Utf8 = New-Object Text.UTF8Encoding($false)
function Write-Json($Value, [string]$Name) {
    $json = ConvertTo-Json -InputObject $Value -Depth 12 -Compress
    [IO.File]::WriteAllText((Join-Path $Repo "data\$Name"), $json, $Utf8)
}
$byName = [Comparison[object]] { param($a, $b) [string]::Compare($a['name']['en'], $b['name']['en'], $true) }
foreach ($list in $gearsets, $brandsets, $exotics, $namedWeapons, $talents) { $list.Sort($byName) }
Write-Json $talents.ToArray() 'talents.json'
Write-Json ([ordered]@{ levelCurve40 = $levelCurve40; levelFormula = $AttrByName['LevelAndTierCurve'].formula; sources = $dotSources.ToArray() }) 'dot.json'
Write-Json $gearsets.ToArray() 'gearsets.json'
Write-Json $brandsets.ToArray() 'brandsets.json'
Write-Json $exotics.ToArray() 'exotics.json'
Write-Json $namedWeapons.ToArray() 'namedweapons.json'
Write-Json $formulas.ToArray() 'formulas.json'

$build = $null
$toc = Join-Path $Game 'hunter\sdf\pc\data\sdf.sdftoc'
if (Test-Path -LiteralPath $toc) {
    $fs = [IO.File]::OpenRead($toc); $b = New-Object byte[] 64; [void]$fs.Read($b, 0, 64); $fs.Close()
    $build = '{0:D4}-{1:D2}-{2:D2}' -f [BitConverter]::ToUInt16($b, 0x24), [BitConverter]::ToUInt16($b, 0x26), [BitConverter]::ToUInt16($b, 0x28)
}
Write-Json ([ordered]@{ build = $build; itemGenerationVersion = $Version; extracted = (Get-Date -Format 'yyyy-MM-dd') }) 'meta.json'
Log "Fertig. Build $build, Daten in $Repo\data"
