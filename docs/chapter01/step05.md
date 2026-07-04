# A Basic Function app.zig is created

## Steps to Understand the functionality of it

- By default the index is set to the ziglang index, if we want to change to mach, use `zigup --mach`. so a minimal arg interator is used to process it, which help to change the mirror index.
- use `Index.fetch(url, buffer)` to down the index json
- use `Schema.Type.parse` to parse the donloaded json
- Extract the `VersionItem{ key, date }` from the parsed json, if using the mach index need to extract the mach specific version by setDifference(machIndex, ziglangIndex).
- If no version is present, exit with info
- then sort the version item based on the date
- now design std in/out loop get the number of target version to download it using `Downloader.downloadToFile`.
