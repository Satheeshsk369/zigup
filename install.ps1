$ProgressPreference = 'SilentlyContinue'

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

switch ($env:PROCESSOR_ARCHITECTURE) { "AMD64" { $arch = "x86_64" } "ARM64" { $arch = "aarch64" } "x86" { $arch = "x86" } default { throw "Unsupported architecture: $($env:PROCESSOR_ARCHITECTURE)" } }

$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/Satheeshsk369/zigup/releases/latest" -Headers @{ "User-Agent" = "zigup-installer" }
if ($rel -is [string]) { $rel = ConvertFrom-Json $rel }
if (-not $rel.tag_name) { throw "Failed to resolve latest release tag" }
$tag = $rel.tag_name

$url    = "https://github.com/Satheeshsk369/zigup/releases/download/$tag/zigup-$arch-windows.exe"
$binDir = Join-Path $env:LOCALAPPDATA "zigup\bin"
$dest   = Join-Path $binDir "zigup.exe"

New-Item -ItemType Directory -Path $binDir -Force | Out-Null
Write-Host "Downloading zigup $tag ($arch)..."
Invoke-WebRequest -Uri $url -OutFile $dest

$rawUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($null -eq $rawUserPath) {
    $rawUserPath = ""
}

# Resolve and clean paths to check if it exists accurately
$userPathList = $rawUserPath -split ";" | Where-Object { $_ } | ForEach-Object {
    $pathItem = $_
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($pathItem).Trim().TrimEnd('\')
        if ($expanded -and [System.IO.Path]::IsPathRooted($expanded)) {
            [System.IO.Path]::GetFullPath($expanded)
        } else {
            $expanded
        }
    } catch {
        $pathItem.Trim().TrimEnd('\')
    }
}
$resolvedBinDir = $binDir.TrimEnd('\')

if ($userPathList -notcontains $resolvedBinDir) {
    $newPath = if ($rawUserPath -eq "") { $binDir } else { $rawUserPath.TrimEnd(';') + ";" + $binDir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:PATH += ";$binDir"
    
    # Notify Windows that environment variables have changed
    $signature = '[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
    $type = Add-Type -MemberDefinition $signature -Name "Win32SendMessage" -Namespace "Win32" -PassThru
    $result = [UIntPtr]::Zero
    $type::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
}
Write-Host "zigup installed. Open a new terminal or run: zigup help"
