const std = @import("std");
const random = @import("../random.zig");
const mix = @import("../mix.zig");

pub fn shuffle(_key: anytype, comptime T: anytype, vals: []T) void {
    var key = _key;
    for (vals) |*v,i| {
        const selection = key.int(usize, i, vals.len-1);
        key = key.split(1)[0];
        const tmp = v.*;
        v.* = vals[selection];
        vals[selection] = tmp;
    }
}

test "shuffle" {
    const key = random.PRNGKey(mix.aes5){.seed = 42};
    var data = [_]u8{1, 2, 3, 4, 5};
    shuffle(key, u8, data[0..]);
    try std.testing.expectEqual(data[0], 3);
    try std.testing.expectEqual(data[1], 5);
    try std.testing.expectEqual(data[2], 1);
    try std.testing.expectEqual(data[3], 4);
    try std.testing.expectEqual(data[4], 2);
}

pub fn permutation(key: anytype, vals: anytype) @TypeOf(vals) {
    const T = @TypeOf(vals);
    const TC = @typeInfo(T).Array.child;
    var rtn: T = undefined;
    std.mem.copy(TC, rtn[0..], vals[0..]);
    shuffle(key, TC, rtn[0..]);
    return rtn;
}

test "permutation" {
    const key = random.PRNGKey(mix.aes5){.seed = 42};
    var data = [_]u8{1, 2, 3, 4, 5};
    var p = permutation(key, data);
    try std.testing.expectEqual(p[0], 3);
    try std.testing.expectEqual(p[1], 5);
    try std.testing.expectEqual(p[2], 1);
    try std.testing.expectEqual(p[3], 4);
    try std.testing.expectEqual(p[4], 2);
    try std.testing.expectEqual(data[0], 1);
    try std.testing.expectEqual(data[1], 2);
    try std.testing.expectEqual(data[2], 3);
    try std.testing.expectEqual(data[3], 4);
    try std.testing.expectEqual(data[4], 5);
}
