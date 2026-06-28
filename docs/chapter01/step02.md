# Serialize and DeSerialize the Json

## Expected
- construct a `Schema` type
- create a `parse(data: []const u8)` function to serailize
- create a `format(...)` function for any std.Io.Writer

## Progress
- So first i need to figure out, how to write the output as a file in zig
- Now schema is created, it perfectly parsing the json both index and accomplished the deserialization.


## Observation
- The ReleaseFast version on index.zig takes only 3sec to download both index json.
- waiting 3sec is ok compared to configuration overhead.
