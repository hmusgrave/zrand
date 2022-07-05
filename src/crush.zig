const std = @import("std");
const random = @import("random.zig");

const crush = @cImport({
    @cInclude("bbattery.h");
    @cInclude("unif01.h");
});

const PT = random.PRNGKey(random.Hashes.aes5);

fn get_u01(_: ?*anyopaque, state: ?*anyopaque) callconv(.C) f64 {
    if (state) |s| {
        var key = @intToPtr(*PT, @ptrToInt(s));
        return key.uniform(1)[0];
    } else {
        unreachable;
    }
}

fn get_bits(_: ?*anyopaque, state: ?*anyopaque) callconv(.C) c_ulong {
    if (state) |s| {
        var key = @intToPtr(*PT, @ptrToInt(s));
        return @truncate(c_ulong, key.random(1)[0]);
    } else {
        unreachable;
    }
}

fn write(state: ?*anyopaque) callconv(.C) void {
    if (state) |s| {
        var key = @intToPtr(*PT, @ptrToInt(s));
        std.debug.print("{}", .{key});
    } else {
        unreachable;
    }
}

pub fn main() anyerror!void {
    var state = PT{.seed=42};
    const _name = "Aes5";
    var name: [_name.len+1:0]u8 = undefined;
    for (name) |*c,i|
        c.* = _name[i];
    var bar = crush.unif01_Gen{
        .state =  &state,
        .param = null,
        .name = &name,
        .GetU01 = get_u01,
        .GetBits = get_bits,
        .Write = write,
    };

    crush.bbattery_SmallCrush(&bar);
    // crush.bbattery_Crush(&bar);
    // crush.bbattery_BigCrush(&bar);
}
