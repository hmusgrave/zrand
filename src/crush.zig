const std = @import("std");

const foo = @cImport({
    @cInclude("TestU01.h");
});

test {
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{@TypeOf(foo.bbattery_SmallCrush)});
}
