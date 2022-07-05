const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = b.addStaticLibrary("zrand", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setTarget(target);
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    var sources = std.ArrayList([]const u8).init(b.allocator);

    // Search for all C/C++ files in `src` and add them
    {
        var dir = try std.fs.cwd().openDir("src", .{ .iterate = true });

        var walker = try dir.walk(b.allocator);
        defer walker.deinit();

        const allowed_exts = [_][]const u8{ ".c" };
        const disallowed_names = [_][]const u8{
            "fftc.c",
            "ucryptoIS.c",
        };
        while (try walker.next()) |entry| {
            const ext = std.fs.path.extension(entry.basename);
            const include_file = for (allowed_exts) |e| {
                if (!std.mem.eql(u8, ext, e))
                    continue;
                const _include_file = for (disallowed_names) |broken| {
                    var m = entry.path.len;
                    m = if (m < broken.len) 0 else m-broken.len;
                    var z = entry.path[m..];
                    if (std.mem.eql(u8, z, broken))
                        break false;
                } else true;
                if (_include_file)
                    break true;
            } else false;
            if (include_file) {
                // we have to clone the path as walker.next() or walker.deinit() will override/kill it
                var path = try b.allocator.alloc(u8, 4+entry.path.len);
                path[0..4].* = "src/".*;
                std.mem.copy(u8, path[4..], entry.path);
                try sources.append(b.dupe(path));
            }
        }
    }

    const crush_tests = b.addTest("src/crush.zig");
    crush_tests.setBuildMode(mode);

    crush_tests.addIncludePath("./src/crush/include");
    crush_tests.addCSourceFiles(sources.items, &[_][]const u8{});
    crush_tests.linkLibC();

    const crush_step = b.step("crush", "Run crush tests");
    crush_step.dependOn(&crush_tests.step);
}
