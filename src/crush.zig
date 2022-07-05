const std = @import("std");

const foo = @cImport({
    @cInclude("bbattery.h");
    @cInclude("bitset.h");
});

fn get_u01(param: ?*anyopaque, state: ?*anyopaque) callconv(.C) f64 {
    _ = param;
    _ = state;
    return 0.0;
}

fn get_bits(param: ?*anyopaque, state: ?*anyopaque) callconv(.C) c_ulong {
    _ = param;
    _ = state;
    return 0;
}

fn write(state: ?*anyopaque) callconv(.C) void {
    _ = state;
}

test {
    var state: u8 = 5;
    var param: u8 = 12;
    var _name = "foo";
    var name = [_:0]u8{_name[0], _name[1], _name[2], 0};
    var bar = foo.unif01_Gen{
        .state =  &state,
        .param = &param,
        .name = &name,
        .GetU01 = get_u01,
        .GetBits = get_bits,
        .Write = write,
    };
    _ = bar;

    foo.bbattery_SmallCrush(&bar);

    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{@TypeOf(foo.bbattery_SmallCrush)});
    std.debug.print("{}\n", .{@TypeOf(foo.unif01_Gen)});
    std.debug.print("{}\n", .{foo.unif01_Gen});
}
