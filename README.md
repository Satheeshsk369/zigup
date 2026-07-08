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

- **`install <TAG>`**: Installs a Zig version. Use `-S` to sync and select from mirrors, `--mirror=<name>` for specific mirrors, or `--url=<url>` for direct links.
- **`default <TAG>`**: Switches the default active Zig compiler version.
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

* By default zigup uses the ziglang mirror, you can just download the tag what you want

  ```bash
  zigup install 0.16.0 # install the 0.16.0 version from ziglang
  zigup default 0.16.0 # you need to explicitly set the default (otherwise zig binary won't exist on first run)
  ```

* you can manage the mirror and default mirror in the config.zon, which helps to use that with `--mirror` option.

  ```bash
  zigup install 0.16.0 --mirror=mach # it shows already exist, even you installed 0.16.0 with other mirror
  zigup delete 0.16.0 # in that case delete it
  zigup install 0.16.0 --mirror=mach # install freshly from the new mirror, if you want so.
  zigup default 0.16.0 # default won't affect unless you want a different tag
  ```

* use the `--url` option, if you don't want to touch the config.zon

  ```bash
  zigup delete 0.16.0 # delete existed installation
  zigup install 0.16.0 --url="https://pkg.hexops.org/zig/index.json"
  zigup default 0.16.0
  ```

* zigup use the cache the json index, if you are working with master always use `-S` for sync

  ```bash
  zigup -S install master # This will first update the json, Then download the zig version
  zigup -S install master --mirror=mach 
  ```

* You can list the tags

  ```bash
  zigup list # list the local installed tags
  zigup list ziglang # list the tags present in ziglang mirror
  zigup -S list mach # sync the index and list the tags present in mach mirror
  ```

* View the env zigup uses
  ```bash
  zigup env # show what are the directly uses for what purpose
  ```

* Self update the zigup

  ```bash
  zigup update
  ```

## GitHub Actions CI/CD Usage

You can use `zigup` to manage and cache the Zig compiler in your GitHub Actions workflows:

```yaml
  - name: Cache Zig compiler installations
    uses: actions/cache@v4
    with:
      path: ~/.local/share/zig
      key: ${{ runner.os }}-zig-0.16.0

  - name: Install latest zigup and Zig 0.16.0
    run: |
      curl -sSfL https://raw.githubusercontent.com/Satheeshsk369/zigup/main/install.sh | sh
      echo "$HOME/.local/bin" >> $GITHUB_PATH
      export PATH="$HOME/.local/bin:$PATH"
      zigup install 0.16.0
      zigup default 0.16.0
    shell: bash
```
