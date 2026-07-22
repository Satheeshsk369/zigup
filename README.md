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

* **`install <TAG>`** (alias **`i`**): Downloads and installs a Zig version. Skips download if already installed. Use `-S` to sync and select from mirrors, `-mirror=<name>` for specific mirrors, or `-url=<url>` for direct links.
* **`set <TAG>`** (alias **`s`**): Sets an installed Zig version as the default/active version.
* **`list [MIRROR]`** (alias **`l`**): Lists locally installed versions (or cached remote versions if a mirror name is provided). Use `-S` to sync.
* **`delete <TAG>`** (alias **`d`**): Uninstalls a local Zig version.
* **`update`** (alias **`up`**): Updates `zigup` to the latest release binary.
* **`env`** (alias **`e`**): Checks if the `~/.local/bin` directory is configured in your system `PATH`.
* **`help`** (alias **`h`**): Prints the help message.
* **`version`** (alias **`v`**): Prints the zigup tool version.

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

* Install a version (this only downloads/extracts it):

  ```bash
  zigup install 0.16.0        # downloads and installs 0.16.0
  ```

* Set an installed version as your active default:

  ```bash
  zigup set 0.16.0            # sets 0.16.0 as active default
  ```

* Switch between installed versions by running `set`:

  ```bash
  zigup set master            # switches active zig to master (if already installed)
  zigup set 0.16.0            # switches back to 0.16.0
  ```

* Manage mirrors in `config.zon`, then use `-mirror`:

  ```bash
  zigup install 0.16.0 -mirror=mach   # install from mach mirror (skips if already present)
  zigup delete 0.16.0                  # delete if you want a clean reinstall from another mirror
  zigup install 0.16.0 -mirror=mach   # fresh install from mach
  ```

* Use `-url` to point at a custom index without touching `config.zon`:

  ```bash
  zigup install 0.16.0 -url="https://pkg.hexops.org/zig/index.json"
  ```

* `master` tracks HEAD — always sync the index before installing:

  ```bash
  zigup -S install master              # sync index, then download latest master
  zigup -S install master -mirror=mach
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
