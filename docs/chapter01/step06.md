# Download Breaks

- When i experimenting with the ui, the download with progress is failed. need to fix the breaking code as high priority before any other features.
- The reason is download is not async, now it upgraded to async to get non blocked. now we just able to download the version in the current folder

## Moving towards simplicity

- Instead of helping to the progress, the UI is add more complexity to the application. so i decided to remove it now and add it later after resolving the abstraction.
- ADT seems powerful and i didn't utilize the full potential yet.
- An idea appear why not make the entire application use a single area allocated memory and use adt to operate on the memory buffer with high level control projection (not now we will see later)

## Simplification

```bash
❯ tree src
src
├── action.zig
├── config.zig
├── download.zig
├── main.zig
└── schema.zig

1 directory, 5 files
```
- entire app is simplified into action, config, download, schema
- the config now properly used the advantage of adt (what i imagined)
- moving towards `~/.zigup/config.zon` and generic mirror url support
