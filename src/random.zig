const std = @import("std");
const Allocator = std.mem.Allocator;
const mix = @import("mix.zig");

fn hash_spec(comptime f: anytype) type {
    const ti = @typeInfo(@TypeOf(f));
    if (ti != .Fn)
        @compileError("Hash must be a function");
    const tif = ti.Fn;
    if (tif.args.len != 1)
        @compileError("Hashes must have exactly one argument");
    if (tif.return_type == null)
        @compileError("Hashes must return a value");
    if (tif.args[0].arg_type == null)
        @compileError("Anytype args unsupported for hashes");
    const In = tif.args[0].arg_type.?;
    const Out = tif.return_type.?;
    if (@typeInfo(In) != .Int)
        @compileError("Hash input must be an integer");
    if (@typeInfo(Out) != .Int)
        @compileError("Hash output must be an integer");
    const tii = @typeInfo(In).Int;
    const tio = @typeInfo(Out).Int;
    if (tii.signedness != .unsigned)
        @compileError("Hash input must be an unsigned integer");
    if (tio.signedness != .unsigned)
        @compileError("Hash output must be an unsigned integer");
    if (tii.bits < tio.bits)
        @compileError("Hash cannot create extra bits of entropy from its inputs");
    if (tio.bits < 1)
        @compileError("Hash must output at least one bit of entropy");
    if (tii.bits & 1 == 1)
        @compileError("Hash must have an even input bit width");
    if (tio.bits & 7 != 0)
        @compileError("Hash must produce full bytes of output");
    return struct {
        pub const in: u16 = tii.bits;
        pub const out: u16 = tio.bits;
    };
}

fn u(comptime bits: anytype) type {
    return @Type(.{.Int = .{
        .signedness = .unsigned,
        .bits = bits,
    }});
}

fn b(comptime T: type) comptime_int {
    return comptime @typeInfo(T).Int.bits;
}

fn isqrt(n: anytype) @TypeOf(n) {
    var x = n;
    var y = (x+1) >> 1;
    while (y < x) {
        x = y;
        y = (x + @divFloor(n, x)) >> 1;
    }
    return x;
}

fn newton_phi(comptime T: type, x: T, c: u(b(T)+2)) T {
    // newton's method for closest integer
    // to c / phi with initial guess x

    const c2 = @intCast(u(b(T)*2+1), c) * c;
    var prev = x;
    var guess = @intCast(T, @divFloor(c2+@intCast(u(b(T)*2), x)*x, (c+x)+x));
    while (guess != prev) {
        const old_guess = guess;
        guess = @intCast(T, @divFloor(c2+@intCast(u(b(T)*2), x)*x, (c+x)+x));
        prev = old_guess;
    }
    return guess;
}

fn odd_gamma(comptime T: type) T {
    if (@typeInfo(T) != .Int)
        @compileError("Only supported on integer types");
    if (@typeInfo(T).Int.signedness != .unsigned)
        @compileError("Only supported on unsigned integers");
    if (T == u0)
        @compileError("u0 has no odd integers");
    const c = @intCast(u(b(T)*2+3), 1) << @typeInfo(T).Int.bits;
    const initial = @intCast(T, (isqrt(5*c*c)-c)>>1);
    const closest = newton_phi(T, initial, @intCast(u(b(T)+2), c));
    const above_root = blk: {
        const z = @intCast(u(b(T)*2), closest);
        const pos = z*(c+z);
        const neg = c*c;
        break :blk pos >= neg;
    };
    const even = (closest & 1) == 0;
    if (!even)
        return closest;
    if (above_root)
        return closest-1;
    return closest+1;
}

test "odd gamma known outputs" {
    // TODO: need to compute the right value eventually, but also this crashes
    // the compiler
    // try std.testing.expectEqual(comptime odd_gamma(u1293), 0);
    try std.testing.expectEqual(comptime odd_gamma(u64), 11400714819323198485);
    try std.testing.expectEqual(comptime odd_gamma(u32), 2654435769);
    try std.testing.expectEqual(comptime odd_gamma(u29), 331804471);
    try std.testing.expectEqual(comptime odd_gamma(u1), 1);
    try std.testing.expectEqual(comptime odd_gamma(u2), 3);
    try std.testing.expectEqual(comptime odd_gamma(u3), 5);
    try std.testing.expectEqual(comptime odd_gamma(u4), 9);
}

test "odd gamma should be odd" {
    @setEvalBranchQuota(3000);
    comptime var i: u16 = 1;
    comptime while (i < 50) : (i += 1)
        try std.testing.expectEqual(odd_gamma(u(i))&1, 1);
}

fn fb(comptime T: type) comptime_int {
    if (T == comptime_float)
        return 128;
    return @typeInfo(T).Float.bits;
}

fn mantissa(comptime T: type) u16 {
    return switch (fb(T)) {
        16 => 10,
        32 => 23,
        64 => 52,
        80 => 64,
        128 => 112,
        else => @compileError("TODO: Unknown floating point type"),
    };
}

fn unifloat(comptime T: type, m: u(fb(T)), e: anytype) T {
    // with exp e==0: float in [1, 2)
    // with exp e==-1: float in [0.5, 1)
    const M = comptime mantissa(T);
    const w = std.math.maxInt(u(M)) + m + 1;
    const mant = std.math.ldexp(@intToFloat(T, w), comptime -@intCast(i32, M));
    return std.math.ldexp(mant, e);
}

// TODO: Allocation and other options
// TODO: Exact uniform floats (all possible values)
pub fn PRNGKey(comptime hash: anytype) type {
    const spec = hash_spec(hash);
    const UI = u(spec.in);
    const UO = u(spec.out);
    const USeed = u(spec.in>>1);

    return struct {
        seed: USeed align(@alignOf(UI)),
        gamma: USeed = odd_gamma(USeed),

        inline fn mix(self: @This(), n: anytype) UO {
            const seed = @intCast(UI, self.seed +% n *% self.gamma) << (spec.in >> 1);
            return hash(seed | self.gamma);
        }

        pub fn fill(self: @This(), comptime T: type) T {
            const N = @sizeOf(T);
            if (N == 0)
                return undefined;

            const hash_bytes = spec.out >> 3;
            const hash_count = 1+@divFloor(N-1, hash_bytes);
            var rtn: T = undefined;
            var rtn_bytes = @ptrCast([*]u8, &rtn)[0..N];
            var entropy: UO = undefined;
            var entropy_bytes = @ptrCast([*]u8, &entropy)[0..hash_bytes];
            var i: usize = 0;
            while (i < hash_count-1) : (i += 1) {
                entropy = self.mix(i);
                std.mem.copy(u8, rtn_bytes[i*hash_bytes..], entropy_bytes);
            }
            entropy = self.mix(i);
            const count = N - (hash_bytes * i);
            std.mem.copy(u8, rtn_bytes[i*hash_bytes..], entropy_bytes[0..count]);
            return rtn;
        }

        pub fn split(self: @This(), comptime n: anytype) [n]@This() {
            var rtn = self.fill([n]@This());
            for (rtn) |*key|
                key.gamma |= 1;
            return rtn;
        }

        pub fn uniform(self: @This(), comptime T: type) T {
            const ti = @typeInfo(T);
            return switch (ti) {
                .Float => blk: {
                    const entropy = self.fill(u(fb(T)));
                    const M = comptime mantissa(T);
                    const m = entropy & std.math.maxInt(u(M));
                    const e = @clz(u(fb(T)-M), @truncate(u(fb(T)-M), entropy >> M));
                    const rtn = unifloat(T, m, -1-@intCast(i32, e));
                    break :blk rtn;
                },
                .ComptimeFloat => self.uniform(f128),
                .Array => switch (@typeInfo(ti.Array.child)) {
                    .Float => float: {
                        const entropy = self.fill([ti.Array.len]u(fb(ti.Array.child)));
                        var rtn: [ti.Array.len]ti.Array.child = undefined;
                        for (entropy) |e,i| {
                            const M = comptime mantissa(ti.Array.child);
                            const m = e & std.math.maxInt(u(M));
                            const IT = u(fb(ti.Array.child)-M);
                            const x = @clz(IT, @truncate(IT, e >> M));
                            rtn[i] = unifloat(ti.Array.child, m, -1-@intCast(i32, x));
                        }
                        break :float rtn;
                    },
                    .ComptimeFloat => self.uniform([ti.Array.len]f128),
                    .Array => arr: {
                        var rtn: T = undefined;
                        const keys = self.split(ti.Array.len);
                        for (keys) |k, i|
                            rtn[i] = k.uniform(ti.Array.child);
                        break :arr rtn;
                    },
                    .Vector => vec: {
                        var rtn: T = undefined;
                        const keys = self.split(ti.Array.len);
                        for (keys) |k, i|
                            rtn[i] = k.uniform(ti.Array.child);
                        break :vec rtn;
                    },
                    else => @compileError("Terminal non-float type not supported"),
                },
                .Vector => blk: {
                    var rtn = self.uniform([ti.Vector.len]ti.Vector.child);
                    break :blk rtn;
                },
                else => @compileError("Non-float type unsupported"),
            };
        }

        pub fn int(self: @This(), comptime T: type, m: anytype, M: anytype) T {
            const ti = @typeInfo(T);
            return switch(ti) {
                .Int => blk: {
                    const U = u(b(T));
                    const U2 = u(b(U)*2);
                    const diff = @bitCast(U, @intCast(T, M)) - @bitCast(U, @intCast(T, m));
                    var entropy = self.fill(U);
                    var wide = @intCast(U2, entropy) *% diff +% entropy;
                    var l = @truncate(U, wide);
                    if (l <= diff) {
                        const t = (1+%~(diff+%1)) % (
                            if (diff < std.math.maxInt(U)) diff+%1
                            else 1
                        );
                        var key = self;
                        while (l < t) {
                            key = key.split(1)[0];
                            entropy = key.fill(U);
                            wide = @intCast(U2, entropy) *% diff +% entropy;
                            l = @truncate(U, wide);
                        }
                    }
                    const delta = @intCast(U, wide >> b(T));
                    const result = @bitCast(U, @intCast(T, m)) +% delta;
                    break :blk @bitCast(T, result);
                },
                .Array => switch (@typeInfo(ti.Array.child)) {
                    .Int => blk: {
                        const L = ti.Array.len;
                        const TC = ti.Array.child;
                        const U = u(b(TC));
                        const U2 = u(b(U)*2);
                        const diff = @bitCast(U, @intCast(TC, M)) - @bitCast(U, @intCast(TC, m));
                        var entropy = self.fill([L]U);
                        var rtn: [L]TC = undefined;
                        var key = self;
                        for (rtn) |*r, i| {
                            // TODO: Zig#11263
                            var x = @intCast(U, entropy[i] & @intCast(u(b(U)+8), std.math.maxInt(U)));
                            var _m = (@intCast(U2, x) * diff) + x;
                            var l = @intCast(U, (_m & std.math.maxInt(U)));
                            if (l <= diff) {
                                const t = (1+%~(diff+%1)) % (
                                    if (diff < std.math.maxInt(U)) diff+%1
                                    else 1
                                );
                                while (l < t) {
                                    key = key.split(1)[0];
                                    x = key.fill(U);
                                    _m = (@intCast(U2, x) *% diff) +% x;
                                    l = @intCast(U, (_m & std.math.maxInt(U)));
                                }
                            }
                            const delta = @intCast(U, _m >> b(U));
                            const result = @bitCast(U, @intCast(TC, m)) +% delta;
                            r.* = @bitCast(TC, result);
                        }
                        break :blk rtn;
                    },
                    // TODO: proper comptime bounds
                    .ComptimeInt => self.int([ti.Array.len]u128, m, M),
                    .Array => {
                        var rtn: T = undefined;
                        var keys = self.split(ti.Array.len);
                        for (rtn) |*r,i|
                            r.* = keys[i].int(ti.Array.child, m, M);
                        return rtn;
                    },
                    .Vector => {
                        var rtn: T = undefined;
                        var keys = self.split(ti.Array.len);
                        for (rtn) |*r,i|
                            r.* = keys[i].int(ti.Array.child, m, M);
                        return rtn;
                    },
                    else => @compileError("Terminal non-int type not supported"),
                },
                // TODO: min size fitting bounds
                .ComptimeInt => self.int(u128, m, M),
                .Vector => blk: {
                    var rtn = self.int([ti.Vector.len]ti.Vector.child, m, M);
                    break :blk rtn;
                },
                else => @compileError("Non-integer type unsupported"),
            };
        }
    };
}

test "randint" {
    const key = PRNGKey(mix.aes5){.seed=42};
    var result = key.int([1][2]i5, 1, 4);
    try std.testing.expectEqual(result[0][0], 4);
    try std.testing.expectEqual(result[0][1], 3);
}

test "uniform" {
    const key = PRNGKey(mix.aes5){.seed=42};
    const a = key.uniform([1][2]@Vector(3, f32));
    const c = key.uniform([1]f64);

    // nested float has correct result
    try std.testing.expectEqual(a[0][0][0], 6.83083057e-01);
    try std.testing.expectEqual(a[0][0][1], 2.09128350e-01);
    try std.testing.expectEqual(a[0][0][2], 2.71442741e-01);
    try std.testing.expectEqual(a[0][1][0], 5.53163170e-01);
    try std.testing.expectEqual(a[0][1][1], 5.92015497e-02);
    try std.testing.expectEqual(a[0][1][2], 7.40262687e-01);
    
    // single float has correct result
    try std.testing.expectEqual(c[0], 5.409501881803329e-01);

    // mean is close to 0.5 -- checks for exponential bias
    const sum100 = @reduce(.Add, key.uniform(@Vector(100, f64)));
    try std.testing.expectEqual(sum100, 4.9395974991959775e+01);
}

test "zero-bit types" {
    // zero-bit values are irrelevant, check that return type is correct
    const key = PRNGKey(mix.aes5){.seed=42};
    try std.testing.expectEqual(void, @TypeOf(key.fill(void)));
    try std.testing.expectEqual([0]u8, @TypeOf(key.fill([0]u8)));
}

test "smaller than hash types" {
    // check that the algo runs on small (and non-byte) types
    const key = PRNGKey(mix.aes5){.seed=42};
    try std.testing.expectEqual(key.fill(u8), 134);
    try std.testing.expectEqual(key.fill(u7), 6);
}

test "equal to hash types" {
    const key = PRNGKey(mix.aes5){.seed=42};
    try std.testing.expectEqual(key.fill(u128), 283113463490563306268068082784508312710);
}

test "greater than hash types" {
    // check a weird-bit-width type greater than the output of aes5
    const key = PRNGKey(mix.aes5){.seed=42};
    const expected = [3]u57{112958837188721798, 71401672777491568, 32373267457401044};
    const result = key.fill([3]u57);
    for (expected) |e,i|
        try std.testing.expectEqual(e, result[i]);
}

test "splitting" {
    // splitting should yield independent variables
    const key = PRNGKey(mix.aes5){.seed=42};
    const keys = key.split(3);
    try std.testing.expectEqual(key.fill(u128), 283113463490563306268068082784508312710);
    try std.testing.expectEqual(keys[0].fill(u128), 133972843923087559519513692840627041177);
    try std.testing.expectEqual(keys[1].fill(u128), 85367320848429821941749986739748641068);
    try std.testing.expectEqual(keys[2].fill(u128), 57633879706798220329671801978213329983);
}
