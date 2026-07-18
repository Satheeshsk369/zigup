# zigup
> zig version manager.

## Install

### Linux & macOS 

```bash
curl -sSfL https://raw.githubusercontent.com/Satheeshsk369/zigup/main/install.sh | sh
```
*Note: Make sure to add `~/.local/bin` to your shell profile `PATH` (e.g. `~/.bashrc`, `~/.zshrc` or `~/.profile`).*

### Windows Powershell

```powershell
powershell -NoProfile -Command "Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/Satheeshsk369/zigup/main/install.ps1')"
```

## Commands

- **`install <TAG>`**: Downloads, installs, and activates a Zig version. Skips download if already installed but always updates the active symlink. Use `-S` to sync and select from mirrors, `--mirror=<name>` for specific mirrors, or `--url=<url>` for direct links.
- **`list [MIRROR]`**: Lists locally installed versions (or cached remote versions if a mirror name is provided). Use `-S` to sync.
- **`delete <TAG>`**: Uninstalls a local Zig version.
- **`update`**: Updates `zigup` to the latest release binary.
- **`env`**: Checks if the `~/.local/bin` directory is configured in your system `PATH`.

## Configuration

`zigup` automatically generates a configuration file at `~/.config/zigup/config.zon` (or `%APPDATA%\zigup\config.zon` on Windows) on its first run. You can add new custom index mirrors directly to this list:
```zig
.{
    .mirrors = .{
        .{ .name = "ziglang", .url = "https://ziglang.org/download/index.json" },
        .{ .name = "mach", .url = "https://pkg.hexops.org/zig/index.json" },
        .{ .name = "my-custom-mirror", .url = "https://example.com/custom/index.json" },
    },
    .defaultMirror = "ziglang",
}
```

## Usage

* By default zigup uses the ziglang mirror. Install a version and it becomes active immediately:

  ```bash
  zigup install 0.16.0        # install 0.16.0 and set it as default
  zigup install 0.16.0        # already installed — just re-activates it
  ```

* Switch between installed versions by running `install` again:

  ```bash
  zigup install master        # switches active zig to master
  zigup install 0.16.0        # switches back to 0.16.0
  ```

* Manage mirrors in `config.zon`, then use `--mirror`:

  ```bash
  zigup install 0.16.0 --mirror=mach   # install from mach mirror (skips if already present)
  zigup delete 0.16.0                  # delete if you want a clean reinstall from another mirror
  zigup install 0.16.0 --mirror=mach   # fresh install from mach
  ```

* Use `--url` to point at a custom index without touching `config.zon`:

  ```bash
  zigup install 0.16.0 --url="https://pkg.hexops.org/zig/index.json"
  ```

* `master` tracks HEAD — always sync the index before installing:

  ```bash
  zigup -S install master              # sync index, then download latest master
  zigup -S install master --mirror=mach
  ```

* List versions:

  ```bash
  zigup list                 # locally installed versions
  zigup list ziglang         # remote versions from ziglang mirror cache
  zigup -S list mach         # sync mach index and list its versions
  ```

* View the paths zigup uses:

  ```bash
  zigup env
  ```

* Self-update zigup:

  ```bash
  zigup update
  ```
