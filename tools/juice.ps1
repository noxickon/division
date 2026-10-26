# Hilfsfunktionen zum Lesen der Snowdrop-Klartextdaten (.juice, .m*, .mdict) und der Lokalisierung (.locpack)

$script:Hex32 = '[0-9A-F]{32}'

# Liest eine Datei in einen Baum aus Bloecken: @{ head; kw; name; uid; props (Liste roher Zeilen); kids (Liste Bloecke) }
function Read-Juice([string]$Path) {
    $root = @{ head = ''; kw = ''; name = ''; uid = $null; props = New-Object System.Collections.Generic.List[string]; kids = New-Object System.Collections.Generic.List[object] }
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($root)
    $lines = [IO.File]::ReadAllLines($Path)
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $t = $lines[$i].Trim()
        if ($t -eq '' -or $t -eq '{' -or $t.StartsWith('include ')) { continue }
        if ($t -eq '}') { if ($stack.Count -gt 1) { [void]$stack.Pop() }; continue }
        $j = $i + 1
        while ($j -lt $lines.Length -and $lines[$j].Trim() -eq '') { $j++ }
        if ($j -lt $lines.Length -and $lines[$j].Trim() -eq '{') {
            $node = New-JuiceNode $t
            $stack.Peek().kids.Add($node)
            $stack.Push($node)
        } else {
            $stack.Peek().props.Add($t)
        }
    }
    return $root
}

function New-JuiceNode([string]$Head) {
    $kw = ($Head -split '\s+', 2)[0]
    $rest = if ($Head.Length -gt $kw.Length) { $Head.Substring($kw.Length).Trim() } else { '' }
    $name = if ($rest -match '^"([^"]*)"') { $Matches[1] } elseif ($rest -match '^(\S+)') { $Matches[1] } else { '' }
    $uid = if ($Head -match "uid=($script:Hex32)") { $Matches[1] } else { $null }
    return @{ head = $Head; kw = $kw; name = $name; uid = $uid; props = New-Object System.Collections.Generic.List[string]; kids = New-Object System.Collections.Generic.List[object] }
}

# Erster Unterblock, dessen Schluesselwort passt
function Get-Kid($Node, [string]$Kw) {
    foreach ($k in $Node.kids) { if ($k.kw -eq $Kw) { return $k } }
    return $null
}

# Alle Bloecke im Teilbaum mit diesem Schluesselwort
function Find-Kids($Node, [string]$Kw) {
    $out = New-Object System.Collections.Generic.List[object]
    $todo = New-Object System.Collections.Generic.Stack[object]
    $todo.Push($Node)
    while ($todo.Count) {
        $n = $todo.Pop()
        foreach ($k in $n.kids) { if ($k.kw -eq $Kw) { $out.Add($k) }; $todo.Push($k) }
    }
    return $out
}

# Wert einer Eigenschaftszeile "key wert" (ohne Anfuehrungszeichen aussen)
function Get-Prop($Node, [string]$Key) {
    foreach ($p in $Node.props) {
        if ($p.StartsWith("$Key ") -or $p -eq $Key) {
            $v = $p.Substring($Key.Length).Trim()
            if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            return $v
        }
    }
    return $null
}

# Verweis "key < uid=.. > = name UID" -> @{ name; uid }
function Get-Ref([string]$Line) {
    if ($Line -match "=\s+(""[^""]+""|\S+)\s+($script:Hex32)\s*$") { return @{ name = $Matches[1].Trim('"'); uid = $Matches[2] } }
    return $null
}

# Lokalisierter Text: liefert @{ guid; text } aus einem Feld wie myUIName "... guid = #X ... text = \"...\""
function Get-LocField([string]$Raw) {
    if (-not $Raw) { return $null }
    $guid = if ($Raw -match "guid = #($script:Hex32)") { $Matches[1] } else { $null }
    $text = $null
    if ($Raw -match 'text = \\"(.*?)\\", type') { $text = $Matches[1] }
    elseif ($Raw -match "text = '(.*?)', type") { $text = $Matches[1] }
    elseif ($Raw -match 'text = \\"(.*?)\\"') { $text = $Matches[1] }
    if ($text) { $text = $text -replace '\\"', '"' -replace '\\n', "`n" }
    return @{ guid = $guid; text = $text }
}

# Liest menus.locpack (CSV: GUID,Version,Text) in eine Hashtable GUID -> Text
function Read-Locpack([string]$Path) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $map = @{}
    $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($Path, [Text.Encoding]::UTF8)
    $parser.SetDelimiters(',')
    $parser.HasFieldsEnclosedInQuotes = $true
    while (-not $parser.EndOfData) {
        try { $f = $parser.ReadFields() } catch { continue }
        if ($f.Length -ge 3 -and $f[0].Length -eq 32) { $map[$f[0]] = $f[2] }
    }
    $parser.Close()
    return $map
}
