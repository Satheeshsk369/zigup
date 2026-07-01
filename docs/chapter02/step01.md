# Set Operation on Zig Type

- Zig has a great type system with the following three core idea
  - `enum` => help to store the different named states together for efficiency and accessibility.
  - `union` => (OR type field) help to represent the dynamic type in a statistically typed language.
  - `struct` => (AND type field) help to grouping individual types together.

## Why need Set

- Zig type system itself is efficient in representing for what we want, but we also need higher level type composition for representation simplicity.
- I need a same Platform type also as enum, so i can easily and another platform if zig extended it. and i also need it as struct to parse the json properly.
- I feel, just the type composition is missing to make our type definition simple on mainataining it. because some type the logic is sparse we need to define the same logic for many types. And I don't want that sparse logic definition.
- According to kolmogorov complexity, the complexity of the information is what a length of the shortest program which generate it. With this composed definition we can able reduce the complexity of the type. (I belive so)

## What Implemented

- In the `src/set.zig`, three main operations are implemented:
  - **Union**: `Union(comptime A: type, comptime B: type) type` - Merges all fields of struct `A` and struct `B`. In case of duplicate field names, fields from `A` take precedence.
  - **Intersection**: `Intersection(comptime A: type, comptime B: type) type` - Computes a new struct containing only the fields that exist in both struct `A` and struct `B`.
  - **Difference**: `Difference(comptime A: type, comptime B: type) type` - Computes a new struct containing only the fields that exist in struct `A` but not in struct `B`.

- Along with the operations, four conversions are implemented to cleanly translate between structs, unions, and enums:
  - **UnionToStruct**: `UnionToStruct(comptime U: type, comptime opt: Options) type` - Converts a union type to a struct type, preserving all field names and types. Supports optional default value assignment through the `Options` struct.
  - **StructToUnion**: `StructToUnion(comptime S: type) type` - Converts a struct type to a tagged union type, tagged by an auto-generated enum.
  - **EnumToUnion**: `EnumToUnion(comptime E: type, comptime T: anytype) type` - Converts an enum type to a tagged union type using the tags of enum `E` and a list of payload types `T`.
  - **UnionToEnum**: `UnionToEnum(comptime U: type) type` - Extracts the underlying enum tag type from a tagged union.
