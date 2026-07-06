$ErrorActionPreference = 'Stop'

# Detect Architecture
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
switch ($arch) {
    'x64'   { $arch = 'x86_64' }
    'arm64' { $arch = 'aarch64' }
    'x86'   { $arch = 'x86' }
    default { throw "Unsupported architecture: $arch" }
}


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tag = "v0.1.0"
try {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/Satheeshsk369/zigup/releases/latest"
    if ($response -is [string]) {
        $release = ConvertFrom-Json $response
    } else {
        $release = $response
    }
    if ($release.tag_name) {
        $tag = $release.tag_name
    }
} catch {}

$binaryName = "zigup-$arch-windows.exe"
$url = "https://github.com/Satheeshsk369/zigup/releases/download/$tag/$binaryName"

$binDir = Join-Path $HOME ".zigup\bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

$destPath = Join-Path $binDir "zigup.exe"

Write-Host "Downloading zigup for windows-$arch..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $destPath

Write-Host "Successfully installed zigup to $destPath"
