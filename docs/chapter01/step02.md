# Serialize and DeSerialize the Json

## Expected
- construct a `Schema` type
- create a `parse(data: []const u8)` function to serailize
- create a `format(...)` function for any std.Io.Writer

## Progress
- So first i need to figure out, how to write the output as a file in zig
- Now schema is created, it perfectly parsing the json both index and accomplished the deserialization.
- since i decided to not to save the fetched result as config. no need to serialize again.

```zig
const parsed = try std.json.parseFromSlice(Schema, gpa, json, .{ .ignore_unknown_fields = true });
defer parsed.deinit();

var it = parsed.value.map.iterator();
while (it.next()) |entry| {
    std.debug.print("Version: {s}, Date: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.date });
}
```

## Observation
- The ReleaseFast version on index.zig takes only 3sec to download both index json.
- waiting 3sec is ok compared to configuration overhead.
- This is fast then i expected, the release fast with download and parse single index takes only less than 2s.
