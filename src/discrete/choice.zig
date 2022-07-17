const std = @import("std");
const Allocator = std.mem.Allocator;
const random = @import("../random.zig");
const mix = @import("../mix.zig");

pub fn choice(key: anytype, comptime T: type, vals: anytype) !T {
    if (vals.len < 1)
        return error.ZeroChoices;
    const Child = @TypeOf(vals[0]);
    if (T == Child)
        return vals[key.int(usize, 0, vals.len-1)];
    const ti = @typeInfo(T);
    return switch(ti) {
        .Array => blk: {
            var keys = key.split(ti.Array.len);
            var rtn: T = undefined;
            for (rtn) |*r,i|
                r.* = try choice(keys[i], ti.Array.child, vals);
            break :blk rtn;
        },
        .Vector => try choice(key, [ti.Vector.len]ti.Vector.child, vals),
        else => @compileError("Unsupported choice"),
    };
}

test "choice" {
    const key = random.PRNGKey(mix.aes5){.seed = 42};
    var data = [_]u8{1, 2, 3, 4, 5};
    var data_slice: []u8 = data[0..];
    var c = choice(key, u8, data_slice);
    try std.testing.expectEqual(c, 3);
    const d = try choice(key, [4][3]u8, data_slice);
    try std.testing.expectEqual(d[0][0], 1);
    try std.testing.expectEqual(d[2][0], 5);
    try std.testing.expectEqual(d[2][1], 2);
}

pub fn enum_choice(key: anytype, comptime T: type) T {
    const ti = @typeInfo(T);
    return switch(ti) {
        .Enum => blk: {
            const fields = @typeInfo(T).Enum.fields;
            const selection = key.int(usize, 0, fields.len-1);
            var rtn: T = undefined;
            inline for (fields) |f,i| {
                if (i == selection) {
                    rtn = @intToEnum(T, f.value);
                    break;
                }
            }
            break :blk rtn;
        },
        .Array => blk: {
            var rtn: T = undefined;
            var keys = key.split(ti.Array.len);
            for (rtn) |*r,i|
                r.* = enum_choice(keys[i], ti.Array.child);
            break :blk rtn;
        },
        else => @compileError("Only arrays and enums are supported"),
    };
}

test "enum" {
    const Foo = enum {
        ok,
        not_ok,
    };

    const key = random.PRNGKey(mix.aes5){.seed = 42};
    var enums = enum_choice(key, [4]Foo);
    try std.testing.expectEqual(Foo.not_ok, enums[0]);
    try std.testing.expectEqual(Foo.not_ok, enums[1]);
    try std.testing.expectEqual(Foo.not_ok, enums[2]);
    try std.testing.expectEqual(Foo.ok, enums[3]);
}

const WeightedCoin = struct {
    prob: f32,
    alias: usize,
};

pub const WeightedChoice = struct {
    table: []WeightedCoin,
    allocator: Allocator,

    pub fn init(allocator: Allocator, weights: anytype) !@This() {
        var t: f32 = 0;
        for (weights) |w|
            t += w;
        var rtn = try allocator.alloc(WeightedCoin, weights.len);
        errdefer allocator.free(rtn);
        var small = try allocator.alloc(WeightedCoin, weights.len);
        defer allocator.free(small);
        var nsmall: usize = 0;
        var large = try allocator.alloc(WeightedCoin, weights.len);
        defer allocator.free(large);
        var nlarge: usize = 0;
        for (weights) |w,i| {
            const p = w * @intToFloat(f32, weights.len) / t;
            if (p < 1) {
                small[nsmall] = .{.prob = p, .alias = i};
                nsmall += 1;
            } else {
                large[nlarge] = .{.prob = p, .alias = i};
                nlarge += 1;
            }
        }
        while (nsmall != 0 and nlarge != 0) {
            const l = small[nsmall-1];
            nsmall -= 1;
            var g = large[nlarge-1];
            nlarge -= 1;
            rtn[l.alias] = .{.prob = l.prob, .alias = g.alias};
            g.prob = (l.prob + g.prob) - 1;
            if (g.prob < 1) {
                small[nsmall] = g;
                nsmall += 1;
            } else {
                large[nlarge] = g;
                nlarge += 1;
            }
        }
        while (nlarge != 0) {
            const g = large[nlarge-1];
            nlarge -= 1;
            rtn[g.alias] = .{.prob = 1, .alias = 0};
        }
        while (nsmall != 0) {
            const l = small[nsmall-1];
            nsmall -= 1;
            rtn[l.alias] = .{.prob = 1, .alias = 0};
        }
        return @This(){.table = rtn, .allocator = allocator};
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.table);
    }

    fn rand(self: @This(), _key: anytype) usize {
        const i = _key.int(usize, 0, self.table.len-1);
        const key = _key.split(1)[0];
        const p = key.uniform(f32);
        const c = self.table[i];
        return if(p <= c.prob) i else c.alias;
    }

    pub fn fill(self: @This(), comptime T: type, key: anytype) T {
        const ti = @typeInfo(T);
        return switch(ti) {
            .Int => self.rand(key),
            .Array => switch(@typeInfo(ti.Array.child)) {
                .Int => blk: {
                    var rtn: T = undefined;
                    var keys = key.split(ti.Array.len);
                    for (rtn) |*r,i|
                        r.* = self.fill(ti.Array.child, keys[i]);
                    break :blk rtn;
                },
                .ComptimeInt => self.fill([ti.Array.len]usize, key),
                .Array => blk: {
                    var rtn: T = undefined;
                    var keys = self.split(ti.Array.len);
                    for (rtn) |*r,i|
                        r.* = self.fill(ti.Array.child, keys[i]);
                    break :blk rtn;
                },
                .Vector => blk: {
                    var rtn: T = undefined;
                    var keys = self.split(ti.Array.len);
                    for (rtn) |*r,i|
                        r.* = self.fill(ti.Array.child, keys[i]);
                    break :blk rtn;
                },
                else => @compileError("Terminal non-int type not supported"),
            },
            .ComptimeInt => self.rand(key),
            .Vector => blk: {
                var rtn = self.fill([ti.Vector.len]ti.Vector.child, key);
                break :blk rtn;
            },
            else => @compileError("Non-integer type unsupported"),
        };
    }

    pub fn fill_from(self: @This(), comptime T: type, key: anytype, choices: anytype) T {
        const ti = @typeInfo(T);
        return switch(ti) {
            .Int => choices[self.rand(key)],
            .Array => switch(@typeInfo(ti.Array.child)) {
                .Int => blk: {
                    var rtn: T = undefined;
                    var keys = key.split(ti.Array.len);
                    for (rtn) |*r,i|
                        r.* = self.fill_from(ti.Array.child, keys[i], choices);
                    break :blk rtn;
                },
                .ComptimeInt => self.fill_from([ti.Array.len]usize, key, choices),
                .Array => blk: {
                    var rtn: T = undefined;
                    var keys = self.split(ti.Array.len);
                    for (rtn) |*r,i|
                        r.* = self.fill_from(ti.Array.child, keys[i], choices);
                    break :blk rtn;
                },
                .Vector => blk: {
                    var rtn: T = undefined;
                    var keys = self.split(ti.Array.len);
                    for (rtn) |*r,i|
                        r.* = self.fill_from(ti.Array.child, keys[i], choices);
                    break :blk rtn;
                },
                else => @compileError("Terminal non-int type not supported"),
            },
            .ComptimeInt => choices[self.rand(key)],
            .Vector => blk: {
                var rtn = self.fill_from([ti.Vector.len]ti.Vector.child, key, choices);
                break :blk rtn;
            },
            else => @compileError("Non-integer type unsupported"),
        };
    }
};


test "weighted choice" {
    const key = random.PRNGKey(mix.aes5){.seed = 42};
    const weights = [_]f32{1, 2, 3.5};
    const table = try WeightedChoice.init(std.testing.allocator, weights);
    defer table.deinit();
    var x = table.fill([5]usize, key);
    try std.testing.expectEqual(x[0], 2);
    try std.testing.expectEqual(x[1], 1);
    try std.testing.expectEqual(x[2], 2);
    try std.testing.expectEqual(x[3], 2);
    try std.testing.expectEqual(x[4], 0);
    const choices = [_]i7{8, 9, 1};
    const y = table.fill_from([5]i7, key, choices);
    try std.testing.expectEqual(y[0], 1);
    try std.testing.expectEqual(y[1], 9);
    try std.testing.expectEqual(y[2], 1);
    try std.testing.expectEqual(y[3], 1);
    try std.testing.expectEqual(y[4], 8);
}
