const std = @import("std");
const Schema = @import("schema.zig");
const download_mod = @import("download.zig");
const config = @import("config.zig");
const Command = config.Command;

pub fn getHomePath(init: std.process.Init, allocator: std.mem.Allocator) ![]const u8 {
    if (init.environ_map.get("HOME")) |home| {
        return allocator.dupe(u8, home);
    } else if (init.environ_map.get("USERPROFILE")) |up| {
        return allocator.dupe(u8, up);
    }
    return error.EnvironmentVariableNotFound;
}

fn getTargetKey() []const u8 {
    const builtin = @import("builtin");
    const arch = @tagName(builtin.target.cpu.arch);
    const os = @tagName(builtin.target.os.tag);
    return arch ++ "-" ++ os;
}

pub fn main(init: std.process.Init) !void {
    const VersionItem = struct { key: []const u8, date: []const u8 };
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        std.debug.print("Usage: zigup <command> [options]\nCommands: help, version, env, install, list, delete\nUse --ziglang or --mach to target remote clouds\n", .{});
        return;
    }

    var cloud_target: ?enum { ziglang, mach } = null;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--ziglang")) {
            cloud_target = .ziglang;
        } else if (std.mem.eql(u8, arg, "--mach")) {
            cloud_target = .mach;
        }
    }

    const command_str = args[1];
    var command: ?Command = null;

    if (std.mem.eql(u8, command_str, "help")) {
        command = .help;
    } else if (std.mem.eql(u8, command_str, "version")) {
        command = .version;
    } else if (std.mem.eql(u8, command_str, "env")) {
        command = .env;
    } else if (std.mem.eql(u8, command_str, "list")) {
        if (cloud_target) |ct| {
            command = switch (ct) {
                .ziglang => .list_ziglang,
                .mach => .list_mach,
            };
        } else {
            command = .list_local;
        }
    } else if (std.mem.eql(u8, command_str, "install")) {
        if (args.len < 3) {
            std.debug.print("error: install requires a tag version\n", .{});
            return;
        }
        if (cloud_target) |ct| {
            command = switch (ct) {
                .ziglang => Command{ .install_ziglang = args[2] },
                .mach => Command{ .install_mach = args[2] },
            };
        } else {
            command = Command{ .install_local = args[2] };
        }
    } else if (std.mem.eql(u8, command_str, "delete")) {
        if (args.len < 3) {
            std.debug.print("error: delete requires a tag version\n", .{});
            return;
        }
        if (cloud_target) |ct| {
            command = switch (ct) {
                .ziglang => Command{ .delete_ziglang = args[2] },
                .mach => Command{ .delete_mach = args[2] },
            };
        } else {
            command = Command{ .delete_local = args[2] };
        }
    }

    if (command == null) {
        std.debug.print("Unknown command: {s}\nUse 'zigup help' for usage details.\n", .{command_str});
        return;
    }

    switch (command.?) {
        .help => {
            std.debug.print("zigup - Zig Version Manager\n\n", .{});
            std.debug.print("Commands:\n", .{});
            std.debug.print("  help              Print this message\n", .{});
            std.debug.print("  version           Print zigup tool version\n", .{});
            std.debug.print("  env               Print status of ~/.zigup/bin in your environment PATH\n", .{});
            std.debug.print("  list              List local installed versions (use --ziglang/--mach for remote clouds)\n", .{});
            std.debug.print("  install <TAG>     Install version <TAG> (use --ziglang/--mach for remote clouds)\n", .{});
            std.debug.print("  delete <TAG>      Delete version <TAG> (use --ziglang/--mach for remote clouds)\n", .{});
        },
        .version => {
            std.debug.print("zigup version 0.1.0\n", .{});
        },
        .env => {
            const home_path = try getHomePath(init, arena);
            const path_env = init.environ_map.get("PATH") orelse "";
            const needle = try std.fs.path.join(arena, &.{ home_path, ".zigup", "bin" });
            if (std.mem.indexOf(u8, path_env, needle) != null) {
                std.debug.print("env status: ~/.zigup/bin is in your PATH\n", .{});
            } else {
                std.debug.print("env status: ~/.zigup/bin is NOT in your PATH. Please add it to configure environment.\n", .{});
            }
        },
        .list_local => {
            const home_path = try getHomePath(init, arena);
            const zigup_dir_path = try std.fs.path.join(arena, &.{ home_path, ".zigup" });

            var dir = std.Io.Dir.openDirAbsolute(io, zigup_dir_path, .{ .iterate = true }) catch |err| {
                std.debug.print("No installed versions found (~/.zigup does not exist): {s}\n", .{@errorName(err)});
                return;
            };
            defer dir.close(io);

            var count: usize = 0;
            var it = dir.iterate();
            while (try it.next(io)) |entry| {
                if (entry.kind == .directory and !std.mem.eql(u8, entry.name, "bin") and !std.mem.eql(u8, entry.name, "tmp")) {
                    std.debug.print(" - {s}\n", .{entry.name});
                    count += 1;
                }
            }

            if (count == 0) {
                std.debug.print("No installed versions found in ~/.zigup/\n", .{});
            }
        },
        .list_ziglang, .list_mach => {
            const is_mach_target = (command.? == .list_mach);
            var index = Schema.Index.init(gpa, io);
            defer index.deinit();

            var http_buf = std.Io.Writer.Allocating.init(gpa);
            defer http_buf.deinit();

            const mirror: Schema.Index.Mirror = if (is_mach_target) .mach else .ziglang;
            std.debug.print("Fetching index...\n", .{});

            const index_response = try index.fetch(mirror, &http_buf);
            if (index_response != .ok) {
                std.debug.print("Failed to fetch index: {s}\n", .{@tagName(index_response)});
                return;
            }

            const schema = try Schema.Type.parse(gpa, http_buf.written());
            defer schema.deinit();

            var versions = std.ArrayList(VersionItem).empty;
            defer versions.deinit(gpa);

            if (is_mach_target) {
                var official_buf = std.Io.Writer.Allocating.init(gpa);
                defer official_buf.deinit();
                if ((try index.fetch(.ziglang, &official_buf)) == .ok) {
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

            std.mem.sort(VersionItem, versions.items, {}, struct {
                fn lessThan(_: void, lhs: VersionItem, rhs: VersionItem) bool {
                    const date_order = std.mem.order(u8, lhs.date, rhs.date);
                    if (date_order != .eq) return date_order == .gt;
                    return std.mem.order(u8, lhs.key, rhs.key) == .gt;
                }
            }.lessThan);

            for (versions.items) |item| {
                std.debug.print(" - {s} ({s})\n", .{ item.key, item.date });
            }
        },
        .install_local => {
            // Local install = set default symlink
            const target_ver = command.?.install_local;

            const home_path = try getHomePath(init, gpa);
            defer gpa.free(home_path);

            const zigup_dir_path = try std.fs.path.join(gpa, &.{ home_path, ".zigup" });
            defer gpa.free(zigup_dir_path);

            const target_install_dir = try std.fs.path.join(gpa, &.{ zigup_dir_path, target_ver });
            const file_exists = if (std.Io.Dir.openDirAbsolute(io, target_install_dir, .{})) |*d| blk: {
                d.close(io);
                break :blk true;
            } else |_| false;

            if (!file_exists) {
                std.debug.print("error: version {s} is not installed locally in ~/.zigup/.\nUse 'zigup install {s} --ziglang' (or --mach) to download it first.\n", .{ target_ver, target_ver });
                return;
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
                    std.debug.print("error: failed to create symlink: {s}\n", .{@errorName(err)});
                    return;
                };
            }

            std.debug.print("Set {s} as default.\n", .{target_ver});
        },
        .install_ziglang, .install_mach => {
            const is_mach_target = (command.? == .install_mach);
            const target_ver = if (is_mach_target) command.?.install_mach else command.?.install_ziglang;

            var index = Schema.Index.init(gpa, io);
            defer index.deinit();

            var http_buf = std.Io.Writer.Allocating.init(gpa);
            defer http_buf.deinit();

            const mirror: Schema.Index.Mirror = if (is_mach_target) .mach else .ziglang;
            std.debug.print("Fetching index...\n", .{});

            const index_response = try index.fetch(mirror, &http_buf);
            if (index_response != .ok) {
                std.debug.print("Failed to fetch index: {s}\n", .{@tagName(index_response)});
                return;
            }

            const schema = try Schema.Type.parse(gpa, http_buf.written());
            defer schema.deinit();

            const platform = Schema.Platform.parse(getTargetKey()) orelse {
                std.debug.print("error: unsupported platform: {s}\n", .{getTargetKey()});
                return;
            };

            const src = schema.get(target_ver, platform) orelse {
                std.debug.print("error: no binary found for version {s} on platform {s}\n", .{ target_ver, getTargetKey() });
                return;
            };

            const home_path = try getHomePath(init, gpa);
            defer gpa.free(home_path);

            const zigup_dir_path = try std.fs.path.join(gpa, &.{ home_path, ".zigup" });
            defer gpa.free(zigup_dir_path);

            const bin_dir_path = try std.fs.path.join(gpa, &.{ zigup_dir_path, "bin" });
            defer gpa.free(bin_dir_path);

            std.Io.Dir.createDirAbsolute(io, zigup_dir_path, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };

            std.Io.Dir.createDirAbsolute(io, bin_dir_path, .default_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };

            var split_it = std.mem.splitBackwardsAny(u8, src.tarball, "/");
            const filename = split_it.first();

            const target_install_dir = try std.fs.path.join(gpa, &.{ zigup_dir_path, target_ver });
            defer gpa.free(target_install_dir);

            const file_exists = if (std.Io.Dir.openDirAbsolute(io, target_install_dir, .{})) |*d| blk: {
                d.close(io);
                break :blk true;
            } else |_| false;

            if (file_exists) {
                std.debug.print("Version {s} is already installed.\n", .{target_ver});
                return;
            }

            std.debug.print("Downloading {s}...\n", .{target_ver});

            var dl = download_mod.Downloader.init(&index.client);
            var file = try std.Io.Dir.createFileAbsolute(io, filename, .{});
            defer file.close(io);

            const result = try download_mod.Downloader.downloadToFile(&dl, src.tarball, file, io);

            if (result.status != .ok) {
                std.debug.print("error: failed to download tarball. HTTP {s}\n", .{@tagName(result.status)});
                return;
            }

            std.debug.print("Extracting to ~/.zigup/{s}...\n", .{target_ver});
            try std.Io.Dir.createDirAbsolute(io, target_install_dir, .default_dir);

            var child = std.process.spawn(io, .{
                .argv = &.{ "tar", "-xf", filename, "-C", target_install_dir, "--strip-components=1" },
            }) catch |err| {
                std.debug.print("error: failed to spawn tar: {s}\n", .{@errorName(err)});
                return;
            };
            const term = child.wait(io) catch |err| {
                std.debug.print("error: failed to wait for tar: {s}\n", .{@errorName(err)});
                return;
            };
            switch (term) {
                .exited => |code| {
                    if (code != 0) {
                        std.debug.print("error: tar extraction failed with exit code {d}\n", .{code});
                        return;
                    }
                },
                else => {
                    std.debug.print("error: tar extraction terminated abnormally\n", .{});
                    return;
                },
            }

            // Cleanup local tar file
            std.Io.Dir.deleteFile(std.Io.Dir.cwd(), io, filename) catch {};

            std.debug.print("Successfully installed version {s}.\n", .{target_ver});
        },
        .delete_local, .delete_ziglang, .delete_mach => {
            const is_mach_target = (command.? == .delete_mach);
            const is_ziglang_target = (command.? == .delete_ziglang);
            const target_ver = if (is_mach_target) command.?.delete_mach else if (is_ziglang_target) command.?.delete_ziglang else command.?.delete_local;

            const home_path = try getHomePath(init, gpa);
            defer gpa.free(home_path);

            const zigup_dir_path = try std.fs.path.join(gpa, &.{ home_path, ".zigup" });
            defer gpa.free(zigup_dir_path);

            const target_install_dir = try std.fs.path.join(gpa, &.{ zigup_dir_path, target_ver });
            defer gpa.free(target_install_dir);

            var z_dir = std.Io.Dir.openDirAbsolute(io, zigup_dir_path, .{}) catch |err| switch (err) {
                else => null,
            };
            if (z_dir) |*zd| {
                defer zd.close(io);
                zd.deleteTree(io, target_ver) catch |err| {
                    std.debug.print("error: failed to delete directory ~/.zigup/{s}: {s}\n", .{ target_ver, @errorName(err) });
                    return;
                };
            }

            std.debug.print("Successfully deleted version {s}.\n", .{target_ver});
        },
    }
}
