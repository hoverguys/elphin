const std = @import("std");
const elf = @import("elf.zig");

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Get args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <input.elf> <output.dol>\n", .{args[0]});
        std.process.exit(1);
    }

    const inputPath = args[1];
    const outputPath = args[2];

    // Read input
    const input = try std.fs.cwd().openFile(inputPath, .{});
    defer input.close();
    var map = try elf.readELF(input);

    // Align segments to 64 byte boundaries
    elf.alignSegments(&map);

    // Write header and copy over segments from input
    const output = try std.fs.cwd().createFile(outputPath, .{});
    defer output.close();
    try elf.writeDOL(map, input, output);
}
