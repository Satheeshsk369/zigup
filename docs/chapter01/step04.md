# Moving towards Stable Abstraction

- Updated the parse/get json logic to schema.
- I try to make the Individual Platform as single enum and make the Version detail struct automatically geenrate it on the comptime. But i don't know how to do it. It's seems decoupling the platform from the version struct will make it more maintainable over time. so currently i'm exporing zig features to achieve it.
