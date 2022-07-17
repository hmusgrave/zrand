const std = @import("std");
const random = @import("../random.zig");
const mix = @import("../mix.zig");

pub fn normal(key: anytype, comptime T: type) T {
    // Ratio of uniforms rejection strategy with a tuned
    // quadratic form to avoid the log computation most
    // of the time
    const ti = @typeInfo(T);
    return switch(ti) {
        .Float, .ComptimeFloat => blk: {
            var keys: [4]@TypeOf(key) = undefined;
            keys[keys.len-1] = key;
            var loc: usize = 3;
            while (true) : ({
                loc += 1;
                keys = if(loc == keys.len) keys[keys.len-1].split(keys.len) else keys;
                loc = loc % keys.len;
            }){
                const uv = keys[loc].uniform([2]T);
                const u = uv[0];
                const v = 1.7156*(uv[1]-0.5);
                const x = u - 0.449871;
                const y = (if (v<0) -v else v) + 0.386595;
                const Q = x*x+y*(0.19600*y-0.25472*x);
                if (u == 0 or Q > 0.27846)
                    continue;
                if (Q < 0.27597)
                    break :blk v/u;
                if (v*v <= -4*u*u*@log(u))
                    break :blk v/u;
            }
        },
        .Vector => blk: {
            var rtn = normal(key, [ti.Vector.len]ti.Vector.child);
            break :blk rtn;
        },
        .Array => blk: {
            var keys = key.split(ti.Array.len);
            var rtn: T = undefined;
            for (rtn) |*r,i|
                r.* = normal(keys[i], ti.Array.child);
            break :blk rtn;
        },
        else => @compileError("Unsupported type"),
    };
}

test "normal" {
    const key = random.PRNGKey(mix.aes5){.seed = 42};
    const x = normal(key, [3]@Vector(4, f32));
    try std.testing.expectEqual(x[0][1], -1.36710810e+00);
    try std.testing.expectEqual(x[2][3], -1.59003221e+00);
    try std.testing.expectEqual(x[2][0], 9.69295352e-02);
}
