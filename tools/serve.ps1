# Kleiner lokaler Webserver zum Ansehen der Seite: http://localhost:8080
param([int]$Port = 8080)
$Repo = Split-Path $PSScriptRoot -Parent
$Types = @{ '.html' = 'text/html; charset=utf-8'; '.json' = 'application/json'; '.md' = 'text/plain; charset=utf-8'; '.png' = 'image/png'; '.svg' = 'image/svg+xml'; '.js' = 'text/javascript'; '.css' = 'text/css' }
$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Server laeuft: http://localhost:$Port/"
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if (-not $path) { $path = 'index.html' }
    $file = [IO.Path]::GetFullPath((Join-Path $Repo $path))
    if ($file.StartsWith($Repo) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
        $bytes = [IO.File]::ReadAllBytes($file)
        $type = $Types[[IO.Path]::GetExtension($file).ToLower()]
        $ctx.Response.ContentType = if ($type) { $type } else { 'application/octet-stream' }
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $ctx.Response.StatusCode = 404
    }
    $ctx.Response.Close()
}
