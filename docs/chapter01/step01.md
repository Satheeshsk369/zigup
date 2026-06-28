# Download the Json Index

## Reference

- https://cookbook.ziglang.cc/05-01-http-get/

## Zig Serve the Json as gzip

- GET:`https://ziglang.org/download/index.json` serves as gzip
- Need to decode from gzip inorder to extract data.
- Good news: Zig has fetch function which automatically decode the data.
- The following code fetch smoothly for both ziglang and mach index.

```zig
const std = @import("std");
const Client = std.http.Client;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var client: Client = .{ .allocator = gpa, .io = init.io };
    defer client.deinit();

    var body = std.Io.Writer.Allocating.init(gpa);
    defer body.deinit();

    const uri = try std.Uri.parse("https://ziglang.org/download/index.json");
    const response = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = &body.writer,
    });

    std.debug.print("Status: {s}", .{@tagName(response.status)});
    std.debug.print("{s}\n", .{body.written()});
}
```

## Observation
- Fetching ziglang index takes 3-4s and mach for 9-10s.
- so it not suitable for live fetch each time. 
- decision: store the index json as local file and parse on runtime
- and `zigup --update` or similar command to update the index file.

## Index URL
- https://ziglang.org/download/index.json
- https://pkg.hexops.org/zig/index.json

