# zigup
> A lightweight, cross-platform Zig version manager built with Zig.

## Install

### Linux & macOS (Single-Line Installer)
This script automatically detects your OS and architecture, downloads the precompiled binary from the latest release, and places it in `~/.zigup/bin/`:

```bash
curl -sSfL https://raw.githubusercontent.com/Satheeshsk369/zigup/main/install.sh | sh
```
*Note: Make sure to add `~/.zigup/bin` to your shell profile `PATH` (e.g. `~/.bashrc`, `~/.zshrc` or `~/.profile`).*

### Windows (Single-Line PowerShell Installer)
Run the following in PowerShell to automatically detect your architecture, download the binary, and place it in `~/.zigup/bin/`:

```powershell
irm https://raw.githubusercontent.com/Satheeshsk369/zigup/main/install.ps1 | iex
```
*Note: Make sure to add `%USERPROFILE%\.zigup\bin` to your environment `PATH` variable.*
