const c = @cImport({
    @cInclude("linux/input.h");
});
const std = @import("std");

// Ew!
pub fn getKey() u4 {
    const dev = "/dev/input/event0";
    var input_event: c.input_event = undefined;
    const file =
        std.fs.openFileAbsolute(dev, .{}) catch {
        return 0;
    };
    var buf: [@sizeOf(c.input_event)]u8 = undefined;
    const bytes_read = file.read(&buf) catch {
        return 9;
    };
    std.debug.print("read({s})\n", .{buf});
    return 1;
}
