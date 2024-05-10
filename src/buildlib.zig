const std = @import("std");
const lib = @import("lib.zig");

const Self = @This();

const ConvertFileOptions = struct {
    installDir: std.Build.InstallDir = .bin,
    filename: ?[]const u8 = null,
};

step: std.Build.Step,
path: std.Build.LazyPath,
options: ConvertFileOptions,

pub fn convertExecutable(b: *std.Build, artifact: *std.Build.Step.Compile, options: ConvertFileOptions) *Self {
    const inputPath = artifact.getEmittedBin();
    const build = convertFile(b, inputPath, options);
    build.step.dependOn(&artifact.step);

    return build;
}

pub fn convertInstalled(b: *std.Build, path: []const u8, options: ConvertFileOptions) *Self {
    const inputPath = b.getInstallPath(options.installDir, path);
    return convertFile(b, .{ .path = inputPath }, options);
}

fn convertFile(b: *std.Build, file: std.Build.LazyPath, options: ConvertFileOptions) *Self {
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

    return self;
}

fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
    const self: *Self = @fieldParentPtr("step", step);
    const b = step.owner;

    // Read input
    const inputPath = self.path.getPath2(b, step);
    const input = try std.fs.cwd().openFile(inputPath, .{});
    defer input.close();

    // Get output path or calculate it from the input
    const name = self.options.filename orelse calculateOutputName(b, std.fs.path.basename(inputPath));
    const destination = b.getInstallPath(self.options.installDir, name);

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
