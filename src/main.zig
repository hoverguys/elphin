const std = @import("std");
const lib = @import("lib.zig");

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Get args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.log.err("Usage: {s} <input.elf> <output.dol>", .{args[0]});
        std.process.exit(1);
    }

    const inputPath = args[1];
    const outputPath = args[2];

    // Read input
    const input = try std.fs.cwd().openFile(inputPath, .{});
    defer input.close();

    // Write header and copy over segments from input
    const output = try std.fs.cwd().createFile(outputPath, .{});
    defer output.close();

    try lib.convert(input, output, true);
}
