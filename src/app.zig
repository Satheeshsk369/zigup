const std = @import("std");
const Schema = @import("schema.zig");
const Downloader = @import("download.zig").Downloader;
const Index = @import("index.zig").Index;
const Mirror = @import("index.zig").Mirror;
const StateMod = @import("state.zig");
const Status = StateMod.Status;

fn getTargetKey() []const u8 {
    const builtin = @import("builtin");
    const arch = @tagName(builtin.target.cpu.arch);
    const os = @tagName(builtin.target.os.tag);
    return arch ++ "-" ++ os;
}

fn getHomePath(init: std.process.Init, allocator: std.mem.Allocator) ![]const u8 {
    if (init.environ_map.get("HOME")) |home| {
        return allocator.dupe(u8, home);
    } else if (init.environ_map.get("USERPROFILE")) |up| {
        return allocator.dupe(u8, up);
    }
    return error.EnvironmentVariableNotFound;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var use_mach = false;
    var is_init = false;
    var shell_name: ?[]const u8 = null;

    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    
    if (args.len >= 2 and std.mem.eql(u8, args[1], "init")) {
        is_init = true;
        if (args.len >= 3) {
            shell_name = args[2];
        }
    }

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--mach")) use_mach = true;
    }

    if (is_init) {
        const home_path = try getHomePath(init, gpa);
        defer gpa.free(home_path);
        const zigup_dir_path = try std.fs.path.join(gpa, &.{ home_path, ".zigup" });
        defer gpa.free(zigup_dir_path);
        const bin_dir_path = try std.fs.path.join(gpa, &.{ zigup_dir_path, "bin" });
        defer gpa.free(bin_dir_path);

        var config_written = false;
        var already_exists = false;
        const shell = shell_name orelse blk: {
            if (init.environ_map.get("SHELL")) |shell_env| {
                var parts = std.mem.splitBackwardsAny(u8, shell_env, "/\\");
                break :blk parts.first();
            }
            break :blk "bash";
        };

        if (std.mem.eql(u8, shell, "fish")) {
            const fish_config_dir = try std.fs.path.join(gpa, &.{ home_path, ".config", "fish" });
            defer gpa.free(fish_config_dir);
            std.Io.Dir.createDirAbsolute(io, fish_config_dir, .default_dir) catch {};
            const config_path = try std.fs.path.join(gpa, &.{ fish_config_dir, "config.fish" });
            defer gpa.free(config_path);

            var file = std.Io.Dir.openFileAbsolute(io, config_path, .{ .mode = .read_write }) catch |err| switch (err) {
                error.FileNotFound => std.Io.Dir.createFileAbsolute(io, config_path, .{ .read = true }) catch |create_err| switch (create_err) {
                    else => null,
                },
                else => null,
            };
            if (file) |*f| {
                defer f.close(io);
                var read_buf: [32768]u8 = undefined;
                var reader = f.reader(io, &read_buf);
                const content = try reader.interface.allocRemaining(gpa, .unlimited);
                defer gpa.free(content);
                const needle = "fish_add_path";
                if (std.mem.indexOf(u8, content, needle) == null) {
                    var write_buf: [1024]u8 = undefined;
                    var writer = f.writer(io, &write_buf);
                    writer.interface.print("\n# zigup path\nfish_add_path {s}\n", .{bin_dir_path}) catch {};
                    _ = writer.interface.flush() catch {};
                    config_written = true;
                } else {
                    already_exists = true;
                }
            }
        } else if (std.mem.eql(u8, shell, "bash") or std.mem.eql(u8, shell, "zsh") or std.mem.eql(u8, shell, "sh")) {
            const config_file_name = if (std.mem.eql(u8, shell, "zsh")) ".zshrc" else ".bashrc";
            const config_path = try std.fs.path.join(gpa, &.{ home_path, config_file_name });
            defer gpa.free(config_path);

            var file = std.Io.Dir.openFileAbsolute(io, config_path, .{ .mode = .read_write }) catch |err| switch (err) {
                error.FileNotFound => std.Io.Dir.createFileAbsolute(io, config_path, .{ .read = true }) catch |create_err| switch (create_err) {
                    else => null,
                },
                else => null,
            };
            if (file) |*f| {
                defer f.close(io);
                var read_buf: [32768]u8 = undefined;
                var reader = f.reader(io, &read_buf);
                const content = try reader.interface.allocRemaining(gpa, .unlimited);
                defer gpa.free(content);
                const needle = ".zigup/bin";
                if (std.mem.indexOf(u8, content, needle) == null) {
                    var write_buf: [1024]u8 = undefined;
                    var writer = f.writer(io, &write_buf);
                    writer.interface.print("\n# zigup path\nexport PATH=\"$HOME/.zigup/bin:$PATH\"\n", .{}) catch {};
                    _ = writer.interface.flush() catch {};
                    config_written = true;
                } else {
                    already_exists = true;
                }
            }
        }

        if (config_written) {
            std.debug.print("Added PATH to shell configuration!\n", .{});
        } else if (already_exists) {
            std.debug.print("PATH already configured.\n", .{});
        } else {
            std.debug.print("Could not update config. Manually add to PATH:\n", .{});
            if (std.mem.eql(u8, shell, "fish")) {
                std.debug.print("fish_add_path $HOME/.zigup/bin\n", .{});
            } else {
                std.debug.print("export PATH=\"$HOME/.zigup/bin:$PATH\"\n", .{});
            }
        }
        return;
    }
    var index = Index.init(gpa, io);
    defer index.deinit();

    var http_buf = std.Io.Writer.Allocating.init(gpa);
    defer http_buf.deinit();

    const mirror_url = if (use_mach) Mirror[1] else Mirror[0];
    std.debug.print("Fetching {s}...\n", .{mirror_url});

    const index_response = try index.fetch(mirror_url, &http_buf);
    if (index_response != .ok) {
        std.debug.print("Failed to fetch index: {s}\n", .{@tagName(index_response)});
        return;
    }

    const schema = try Schema.Type.parse(gpa, http_buf.written());
    defer schema.deinit();

    const VersionItem = struct {
        key: []const u8,
        date: []const u8,
    };

    var versions = std.ArrayList(VersionItem).empty;
    defer versions.deinit(gpa);

    if (use_mach) {
        var official_buf = std.Io.Writer.Allocating.init(gpa);
        defer official_buf.deinit();
        if ((try index.fetch(Mirror[0], &official_buf)) == .ok) {
            const official_schema = try Schema.Type.parse(gpa, official_buf.written());
            defer official_schema.deinit();
            var buf_keys: [200][]const u8 = undefined;
            for (Schema.diff(schema, official_schema, &buf_keys)) |key| {
                if (schema.parsed.value.map.get(key)) |detail| {
                    try versions.append(gpa, .{ .key = key, .date = &detail.date });
                }
            }
        }
    } else {
        var it = schema.parsed.value.map.iterator();
        while (it.next()) |entry| {
            try versions.append(gpa, .{ .key = entry.key_ptr.*, .date = &entry.value_ptr.date });
        }
    }

    if (versions.items.len == 0) {
        std.debug.print("No matching versions found.\n", .{});
        return;
    }

    std.mem.sort(VersionItem, versions.items, {}, struct {
        fn lessThan(_: void, lhs: VersionItem, rhs: VersionItem) bool {
            const date_order = std.mem.order(u8, lhs.date, rhs.date);
            if (date_order != .eq) return date_order == .gt;
            return std.mem.order(u8, lhs.key, rhs.key) == .gt;
        }
    }.lessThan);

    // Set up paths: $HOME/.zigup/
    const home_path = try getHomePath(init, gpa);
    defer gpa.free(home_path);

    const zigup_dir_path = try std.fs.path.join(gpa, &.{ home_path, ".zigup" });
    defer gpa.free(zigup_dir_path);

    // Ensure $HOME/.zigup/ directory exists
    std.Io.Dir.createDirAbsolute(io, zigup_dir_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var default_version: ?[]const u8 = null;
    var state = try StateMod.State.init(gpa, versions.items.len);
    defer state.deinit();
    var bin_dir = std.Io.Dir.openDirAbsolute(io, zigup_dir_path, .{}) catch |err| switch (err) {
        else => null,
    };
    if (bin_dir) |*bd| {
        defer bd.close(io);
        var link_buf: [1024]u8 = undefined;
        if (bd.readLink(io, "bin/zig", &link_buf)) |target_len| {
            const target_path = link_buf[0..target_len];
            var path_parts = std.mem.splitBackwardsAny(u8, target_path, "/\\");
            const first = path_parts.next(); // "zig"
            if (first != null and std.mem.eql(u8, first.?, "zig")) {
                if (path_parts.next()) |ver_name| {
                    default_version = try gpa.dupe(u8, ver_name);
                }
            }
        } else |_| {}
    }
    defer if (default_version) |dv| gpa.free(dv);

    for (versions.items, 0..) |item, idx| {
        const platform = Schema.Platform.parse(getTargetKey()) orelse continue;
        _ = schema.get(item.key, platform) orelse continue;
        var status: Status = .missing;
        const ver_dir_path = try std.fs.path.join(gpa, &.{ zigup_dir_path, item.key });
        defer gpa.free(ver_dir_path);

        var ver_dir = std.Io.Dir.openDirAbsolute(io, ver_dir_path, .{}) catch |err| switch (err) {
            else => null,
        };
        if (ver_dir) |*vd| {
            defer vd.close(io);
            var zig_file = vd.openFile(io, "zig", .{}) catch |err| switch (err) {
                else => null,
            };
            if (zig_file) |*zf| {
                zf.close(io);
                status = .downloaded;
                if (default_version) |dv| {
                    if (std.mem.eql(u8, dv, item.key)) {
                        status = .default;
                    }
                }
            }
        }
        state.set(idx, status);

        const color = switch (status) {
            .missing => "\x1b[37m",
            .fetching => "",
            .corrupted => "\x1b[31m",
            .downloaded => "\x1b[34m",
            .default => "\x1b[32m",
        };
        const suffix = switch (status) {
            .default => " (default)",
            .downloaded => " (downloaded)",
            else => "",
        };
        std.debug.print("{s}{d:>3}) {s}{s}\x1b[0m\n", .{ color, idx, item.key, suffix });
    }

    var stdin_buf: [128]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buf);
    var stdin_iface = &stdin_reader.interface;

    std.debug.print("\nSelect index (q to quit) : ", .{});

    while (true) {
        const line = (try stdin_iface.takeDelimiter('\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, " \r\n");

        if (std.mem.eql(u8, trimmed, "q")) break;
        if (trimmed.len == 0) {
            std.debug.print("Select index (q to quit) : ", .{});
            continue;
        }

        const selected_idx = std.fmt.parseInt(usize, trimmed, 10) catch {
            std.debug.print("Invalid index. Enter a number or 'q': ", .{});
            continue;
        };

        if (selected_idx >= versions.items.len) {
            std.debug.print("Index out of range (0-{d}): ", .{versions.items.len - 1});
            continue;
        }

        const target_ver = versions.items[selected_idx].key;
        const platform = Schema.Platform.parse(getTargetKey()) orelse {
            std.debug.print("error: unsupported platform: {s}\n", .{getTargetKey()});
            return;
        };
        const src = schema.get(target_ver, platform) orelse {
            std.debug.print("error: no binary for {s} on {s}\n\nSelect index (q to quit) : ", .{ target_ver, getTargetKey() });
            continue;
        };

        const current_status = state.get(selected_idx);
        std.debug.print("\n{s} ({s})\n1: download\n2: delete\n3: set default\nq: back\n\nEnter option: ", .{ target_ver, current_status.toString() });

        const opt_line = (try stdin_iface.takeDelimiter('\n')) orelse break;
        const opt_trimmed = std.mem.trim(u8, opt_line, " \r\n");

        if (std.mem.eql(u8, opt_trimmed, "q")) {
            std.debug.print("\nSelect index (q to quit) : ", .{});
            continue;
        }

        if (std.mem.eql(u8, opt_trimmed, "1")) {
            if (current_status == .downloaded or current_status == .default) {
                std.debug.print("Already installed.\n\nSelect index (q to quit) : ", .{});
                continue;
            }

            state.set(selected_idx, .fetching);

            var split_it = std.mem.splitBackwardsAny(u8, src.tarball, "/");
            const filename = split_it.first();

            // tmp folder for download tar
            const tmp_dir_path = try std.fs.path.join(gpa, &.{ zigup_dir_path, "tmp" });
            defer gpa.free(tmp_dir_path);
            std.Io.Dir.createDirAbsolute(io, tmp_dir_path, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };

            const tar_filepath = try std.fs.path.join(gpa, &.{ tmp_dir_path, filename });
            defer gpa.free(tar_filepath);

            std.debug.print("Downloading...\n", .{});

            var dl = Downloader.init(&index.client);
            var file = std.Io.Dir.createFileAbsolute(io, tar_filepath, .{}) catch |err| {
                std.debug.print("Failed to create temp file: {s}\n", .{@errorName(err)});
                state.set(selected_idx, .corrupted);
                std.debug.print("\nSelect index (q to quit) : ", .{});
                continue;
            };
            var target_status = state.get(selected_idx);
            const result = Downloader.downloadToFile(&dl, src.tarball, file, io, &target_status) catch |err| {
                file.close(io);
                std.debug.print("Download error: {s}\n", .{@errorName(err)});
                state.set(selected_idx, .corrupted);
                std.debug.print("\nSelect index (q to quit) : ", .{});
                continue;
            };
            file.close(io);

            if (result.status != .ok) {
                std.debug.print("HTTP error status: {s}\n", .{@tagName(result.status)});
                state.set(selected_idx, .corrupted);
                std.debug.print("\nSelect index (q to quit) : ", .{});
                continue;
            }

            // Extract to $HOME/.zigup/<version>/
            const target_install_dir = try std.fs.path.join(gpa, &.{ zigup_dir_path, target_ver });
            defer gpa.free(target_install_dir);

            // Clean up target directory if exists
            var z_dir = std.Io.Dir.openDirAbsolute(io, zigup_dir_path, .{}) catch |err| switch (err) {
                else => null,
            };
            if (z_dir) |*zd| {
                defer zd.close(io);
                zd.deleteTree(io, target_ver) catch {};
            }
            std.Io.Dir.createDirAbsolute(io, target_install_dir, .default_dir) catch {};

            std.debug.print("\nExtracting tarball...\n", .{});
            
            // Execute extraction
            var child = std.process.spawn(io, .{
                .argv = &.{ "tar", "-xf", tar_filepath, "-C", target_install_dir, "--strip-components=1" },
            }) catch |err| {
                std.debug.print("Failed to run tar: {s}\n", .{@errorName(err)});
                state.set(selected_idx, .corrupted);
                std.debug.print("\nSelect index (q to quit) : ", .{});
                continue;
            };

            const term = child.wait(io) catch |err| {
                std.debug.print("Failed to wait for tar: {s}\n", .{@errorName(err)});
                state.set(selected_idx, .corrupted);
                std.debug.print("\nSelect index (q to quit) : ", .{});
                continue;
            };

            switch (term) {
                .exited => |code| {
                    if (code == 0) {
                        state.set(selected_idx, .downloaded);
                        std.debug.print("Installed successfully to {s}\n", .{target_install_dir});
                        // clean up downloaded tar file
                        if (z_dir) |*zd| {
                            zd.deleteFile(io, tar_filepath) catch {};
                        }
                    } else {
                        std.debug.print("tar exited with non-zero code: {d}\n", .{code});
                        state.set(selected_idx, .corrupted);
                    }
                },
                else => {
                    std.debug.print("tar command terminated abnormally\n", .{});
                    state.set(selected_idx, .corrupted);
                },
            }
        } else if (std.mem.eql(u8, opt_trimmed, "2")) {
            // Delete installed version
            var z_dir = std.Io.Dir.openDirAbsolute(io, zigup_dir_path, .{}) catch |err| switch (err) {
                else => null,
            };
            if (z_dir) |*zd| {
                defer zd.close(io);
                zd.deleteTree(io, target_ver) catch |err| {
                    std.debug.print("Delete error: {s}\n", .{@errorName(err)});
                    std.debug.print("\nSelect index (q to quit) : ", .{});
                    continue;
                };
            }

            // If we deleted the default one, check if we need to remove the symlink
            if (current_status == .default) {
                const bin_dir_path = try std.fs.path.join(gpa, &.{ zigup_dir_path, "bin" });
                defer gpa.free(bin_dir_path);
                const symlink_path = try std.fs.path.join(gpa, &.{ bin_dir_path, "zig" });
                defer gpa.free(symlink_path);
                if (z_dir) |*zd| {
                    zd.deleteFile(io, symlink_path) catch {};
                }
                default_version = null;
            }
            state.set(selected_idx, .missing);
            std.debug.print("Deleted {s}\n", .{target_ver});
        } else if (std.mem.eql(u8, opt_trimmed, "3")) {
            // Set default version
            const current_val = state.get(selected_idx);
            if (current_val == .missing or current_val == .corrupted) {
                std.debug.print("Please download and install the version first.\n", .{});
                std.debug.print("\nSelect index (q to quit) : ", .{});
                continue;
            }

            const bin_dir_path = try std.fs.path.join(gpa, &.{ zigup_dir_path, "bin" });
            defer gpa.free(bin_dir_path);
            std.Io.Dir.createDirAbsolute(io, bin_dir_path, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };

            const symlink_path = try std.fs.path.join(gpa, &.{ bin_dir_path, "zig" });
            defer gpa.free(symlink_path);

            const target_bin_rel = try std.fs.path.join(gpa, &.{ "..", target_ver, "zig" });
            defer gpa.free(target_bin_rel);

            var z_dir = std.Io.Dir.openDirAbsolute(io, zigup_dir_path, .{}) catch |err| switch (err) {
                else => null,
            };
            if (z_dir) |*zd| {
                defer zd.close(io);
                zd.deleteFile(io, symlink_path) catch {};
                zd.symLink(io, target_bin_rel, symlink_path, .{}) catch |err| {
                    std.debug.print("Failed to create symlink: {s}\n", .{@errorName(err)});
                    std.debug.print("\nSelect index (q to quit) : ", .{});
                    continue;
                };
            }

            for (versions.items, 0..) |_, idx| {
                if (state.get(idx) == .default) {
                    state.set(idx, .downloaded);
                }
            }
            state.set(selected_idx, .default);
            if (default_version) |dv| gpa.free(dv);
            default_version = try gpa.dupe(u8, target_ver);

            std.debug.print("Set {s} as default\n", .{target_ver});
        } else {
            std.debug.print("Invalid option.\n", .{});
        }

        std.debug.print("\nSelect index (q to quit) : ", .{});
    }
}
