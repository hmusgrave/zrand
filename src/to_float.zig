const std = @import("std");
const testing = std.testing;

fn _u(comptime x: comptime_int) type {
    return @Type(.{.Int=.{
        .signedness = .unsigned,
        .bits = x,
    }});
}   
        
fn _f(comptime x: comptime_int) type {
    return @Type(.{.Float=.{
        .bits = x,
    }});
}   

fn _gen_to_float(comptime bias: anytype, comptime exp: anytype, comptime man: anytype) fn (_u(1+exp+man)) _f(1+exp+man) {
    // Generating unbiased floats doesn't require many bits on average but
    // requires quite a few in the worst case. Here we have a reasonable
    // compromise that uses as many bits as possible to convert an unsigned int
    // to an equal bit-width float. The mantissa is 1:1, and the sign/exp bits
    // are exponentially weighted to undo IEE754's bias toward near-0 floats.
    //
    // - Can't possibly have a better solution without more bits of entropy.
    // - Operations are pretty fast -- clz, bitwise, add, mul.
    // - f80 is super weird on my computer, totally ignoring for now.
    const C = 1+exp+man;
    const U = _u(C);
    const F = _f(C);
    return struct {
        pub fn f(x: U) F {
            const z: U = @as(_u(exp), bias+exp) - @clz(_u(exp), @truncate(_u(exp), x >> man));
            const w: U = (z << man) + (std.math.maxInt(_u(man)) & x);
            const q: F = 1 / ((@intToFloat(F, bias) + 1) * 4 - 1);
            return (@bitCast(F, w) - 1) * q;
        }
    }.f;
}

pub const uniform_exact_16 = _gen_to_float(15, 5, 10);
pub const uniform_exact_32 = _gen_to_float(127, 8, 23);
pub const uniform_exact_64 = _gen_to_float(1023, 11, 52);
pub const uniform_exact_128 = _gen_to_float(16383, 15, 112);

fn in_range(comptime man: anytype, comptime exp: anytype, comptime eps:
anytype, comptime f: anytype) anyerror!void {
    // The functions under test map uxxx to fxxx in [0, 1]
    // Test the least and greatest inputs to ensure they're
    // exactly 0 and close to (at most) 1.
    const w = f(0);
    const W = f(std.math.maxInt(_u(man)) + (std.math.maxInt(_u(exp+1)) << man));
    try testing.expect(w == 0);
    try testing.expect(W <= 1);
    try testing.expect(W >= 1 - eps);
}

test "in range 128" {
    try in_range(112, 15, 0.0000000000000000000000000000000001, uniform_exact_128);
}

test "in range 64" {
    try in_range(52, 11, 0.0000000000000001, uniform_exact_64);
}

test "in range 32" {
    try in_range(23, 8, 0.0000001, uniform_exact_32);
}

test "in range 16" {
    try in_range(10, 5, 0.001, uniform_exact_16);
}
