const native_endian = @import("builtin").target.cpu.arch.endian();
const std = @import("std");

// This is in nightly but they haven't been making builds for a while
pub fn writeStructEndian(writer: anytype, value: anytype, endian: std.builtin.Endian) anyerror!void {
    if (native_endian == endian) {
        return writer.writeStruct(value);
    } else {
        var copy = value;
        std.mem.byteSwapAllFields(@TypeOf(value), &copy);
        return writer.writeStruct(copy);
    }
}
