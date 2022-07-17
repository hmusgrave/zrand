const std = @import("std");
const Allocator = std.mem.Allocator;
const random = @import("../random.zig");
const mix = @import("../mix.zig");

pub fn bernoulli(key: anytype, comptime T: type, p: anytype) T {
    const ti = @typeInfo(T);
    return switch(ti) {
        .Int, .Float, .ComptimeInt, .ComptimeFloat => @as(T, if (key.uniform(f32) < p) 1 else 0),
        .Bool => key.uniform(f32) < p,
        .Vector => bernoulli(key, [ti.Vector.len]ti.Vector.child, p),
        .Array => blk: {
            var keys = key.split(ti.Array.len);
            var rtn: T = undefined;
            for (rtn) |*r,i|
                r.* = bernoulli(keys[i], ti.Array.child, p);
            break :blk rtn;
        },
        else => @compileError("Unsupported type"),
    };
}

test "bernoulli" {
    const key = random.PRNGKey(mix.aes5){.seed = 42};
    const x = bernoulli(key, [3]u2, 0.7);
    try std.testing.expectEqual(x[0], 1);
    try std.testing.expectEqual(x[1], 1);
    try std.testing.expectEqual(x[2], 0);
}
