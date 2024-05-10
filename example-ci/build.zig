const std = @import("std");
const elphin = @import("elphin");

pub fn build(b: *std.Build) void {
    const file = b.addInstallBinFile(.{ .path = "../testdata/example.elf" }, "lol.elf");

    const convert = elphin.buildlib.convertFile(b, "lol.elf", .{});

    b.getInstallStep().dependOn(&file.step);
    b.getInstallStep().dependOn(&convert.step);
}
