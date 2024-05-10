const std = @import("std");
const lib = @import("lib.zig");

const Self = @This();

const ConvertFileOptions = struct {
    installDir: std.Build.InstallDir = .bin,
    filename: ?[]const u8 = null,
};

step: std.Build.Step,
path: []const u8,
options: ConvertFileOptions,

pub fn convertFile(b: *std.Build, file: []const u8, options: ConvertFileOptions) *Self {
    const convert = b.step("convert", "Converts the compiled .elf file into .dol");

    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = b.fmt("Convert to DOL", .{}),
            .owner = b,
            .makeFn = make,
        }),
        .path = file,
        .options = options,
    };

    convert.dependOn(&self.step);

    return self;
}

fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
    const self: *Self = @fieldParentPtr("step", step);
    const b = step.owner;

    // Get input path
    const inputPath = b.getInstallPath(self.options.installDir, self.path);

    // Read input
    const input = try std.fs.cwd().openFile(inputPath, .{});
    defer input.close();

    // Get output path or calculate it from the input
    const destination = if (self.options.filename) |name|
        b.getInstallPath(self.options.installDir, name)
    else
        calculateOutputName(b, inputPath);

    // Create output file
    const output = try std.fs.cwd().createFile(destination, .{});
    defer output.close();

    try lib.convert(input, output);
}

fn calculateOutputName(b: *std.Build, path: []const u8) []const u8 {
    const extIndex = std.mem.lastIndexOfScalar(u8, path, '.');
    const filenameWithoutExtension = if (extIndex) |index| path[0..index] else path;
    return b.fmt("{s}.dol", .{filenameWithoutExtension});
}
