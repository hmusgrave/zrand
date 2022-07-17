const std = @import("std");

pub const normal = @import("continuous/normal.zig").normal;

test "continuous" {
    std.testing.refAllDecls(@This());
}
