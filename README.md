# zigup
> zig version manager.

## Install

Run the following script to automatically detect your architecture, download the binary, and place it in `~/.zigup/bin/`

> currently the script to install zigup is not widely tested and may fail to download in some platform. if in that case, download the release manually or build the project manually to install zigup in your system.

### Linux & macOS 

```bash
curl -sSfL https://raw.githubusercontent.com/Satheeshsk369/zigup/main/install.sh | sh
```
*Note: Make sure to add `~/.zigup/bin` to your shell profile `PATH` (e.g. `~/.bashrc`, `~/.zshrc` or `~/.profile`).*

### Windows 

```powershell
irm https://raw.githubusercontent.com/Satheeshsk369/zigup/main/install.ps1 | iex
```
*Note: Make sure to add `%USERPROFILE%\.zigup\bin` to your environment `PATH` variable.*


## Commands

- **`install <TAG>`**: Installs a Zig version. Use `-S` to sync and select from mirrors, `--mirror=<name>` for specific mirrors, or `--url=<url>` for direct links.
- **`default <TAG>`**: Switches the default active Zig compiler version.
- **`list [MIRROR]`**: Lists locally installed versions (or cached remote versions if a mirror name is provided). Use `-S` to sync.
- **`delete <TAG>`**: Uninstalls a local Zig version.
- **`update`**: Updates `zigup` to the latest release binary.
- **`env`**: Checks if the `~/.zigup/bin` directory is configured in your system `PATH`.

## Configuration

`zigup` automatically generates a configuration file at `~/.zigup/config.zon` on its first run. You can add new custom index mirrors directly to this list:

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

## Command Examples

* **Sync index and list remote versions**:
  ```bash
  zigup -S list ziglang
  ```
* **Install a version using the default mirror**:
  ```bash
  zigup install 0.16.0
  ```
* **Install the latest master/nightly version**:
  ```bash
  zigup -S install master
  ```
* **Install from a specific mirror**:
  ```bash
  zigup -S install 2026.6.18-mach --mirror=mach
  ```
* **Set version as the active default**:
  ```bash
  zigup default 0.16.0
  ```
* **Delete an installed version**:
  ```bash
  zigup delete 0.15.2
  ```
* **Update zigup itself**:
  ```bash
  zigup update
  ```
