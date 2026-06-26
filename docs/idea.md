# zigup
> zig version manager

## Goals

- Trying to achieve a `ghcup` like zig version manager 
- Support for both cli and tui(default)
- Support for multiple download index json (ziglang, mach) 

## Preference

- use `vaxis` for tui library

## Idea

- Download Json index 
- Parse the Json
- Extract the version
- Install the selected version either via cli or tui
- Symbolic link the default
