$ProgressPreference = 'SilentlyContinue'

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

switch ($env:PROCESSOR_ARCHITECTURE) { "AMD64" { $arch = "x86_64" } "ARM64" { $arch = "aarch64" } "x86" { $arch = "x86" } default { throw "Unsupported architecture: $($env:PROCESSOR_ARCHITECTURE)" } }

$tag = "v0.2.0"
try { $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/Satheeshsk369/zigup/releases/latest" -Headers @{ "User-Agent" = "zigup-installer" }; if ($rel -is [string]) { $rel = ConvertFrom-Json $rel }; if ($rel.tag_name) { $tag = $rel.tag_name } } catch {}

$url    = "https://github.com/Satheeshsk369/zigup/releases/download/$tag/zigup-$arch-windows.exe"
$binDir = Join-Path $env:LOCALAPPDATA "zigup\bin"
$dest   = Join-Path $binDir "zigup.exe"

New-Item -ItemType Directory -Path $binDir -Force | Out-Null
Write-Host "Downloading zigup $tag ($arch)..."
Invoke-WebRequest -Uri $url -OutFile $dest

$userPath = [Environment]::GetEnvironmentVariable("Path", "User") -split ";" | Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd('\') }
if ($userPath -notcontains $binDir.TrimEnd('\')) {
    [Environment]::SetEnvironmentVariable("Path", ($userPath + $binDir) -join ";", "User")
    $env:PATH += ";$binDir"
}
Write-Host "zigup installed. Open a new terminal or run: zigup help"
