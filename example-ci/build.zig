const std = @import("std");
const elphin = @import("elphin");

pub fn build(b: *std.Build) void {
    const file = b.addInstallBinFile(b.path("../testdata/example.elf"), "lol.elf");
    b.getInstallStep().dependOn(&file.step);

    const convert = elphin.convertInstalled(b, "lol.elf", .{});
    b.getInstallStep().dependOn(&convert.step);
}
