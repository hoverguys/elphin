const std = @import("std");
const elf = @import("elf.zig");
const oldzig = @import("oldzig.zig");

pub const MaximumTextSegments = 7;
pub const MaximumDataSegments = 11;

pub const DolHeader = extern struct {
    textOffsets: [7]u32,
    dataOffsets: [11]u32,
    textAddress: [7]u32,
    dataAddress: [11]u32,
    textSize: [7]u32,
    dataSize: [11]u32,
    BSSAddress: u32,
    BSSSize: u32,
    entrypoint: u32,
    reserved: [7]u32,
};

pub const DolMap = struct {
    header: DolHeader,
    textCount: u32,
    dataCount: u32,
    originalFileTextOffset: [7]u32,
    originalFileDataOffset: [11]u32,
};

const DOLAlignment = 64;
pub fn createDOLMapping(segments: elf.ELFSegments) DolMap {
    // Create dol map
    var dolMap = DolMap{
        .header = .{
            .textOffsets = .{0} ** 7,
            .dataOffsets = .{0} ** 11,
            .textAddress = .{0} ** 7,
            .dataAddress = .{0} ** 11,
            .textSize = .{0} ** 7,
            .dataSize = .{0} ** 11,
            .BSSAddress = segments.bssAddress,
            .BSSSize = segments.bssSize,
            .entrypoint = segments.entryPoint,
            .reserved = .{0} ** 7,
        },
        .textCount = segments.textCount,
        .dataCount = segments.dataCount,
        .originalFileTextOffset = undefined,
        .originalFileDataOffset = undefined,
    };

    // Setup dummy segments if no TEXT or DATA segments are present
    dolMap.header.textOffsets[0] = std.mem.alignForward(u32, @sizeOf(DolHeader), DOLAlignment);
    dolMap.header.dataOffsets[0] = std.mem.alignForward(u32, @sizeOf(DolHeader), DOLAlignment);

    var currentPosition = std.mem.alignForward(u32, @sizeOf(DolHeader), DOLAlignment);

    for (0..segments.textCount) |i| {
        // Set offset to aligned address
        dolMap.header.textOffsets[i] = currentPosition;

        // Copy over text segment info
        dolMap.originalFileTextOffset[i] = segments.text[i].offset;
        dolMap.header.textAddress[i] = segments.text[i].address;
        dolMap.header.textSize[i] = segments.text[i].size;

        // Get next aligned position
        currentPosition = std.mem.alignForward(u32, currentPosition + dolMap.header.textSize[i], DOLAlignment);
    }

    for (0..segments.dataCount) |i| {
        // Set offset to aligned address
        dolMap.header.dataOffsets[i] = currentPosition;

        // Copy over text segment info
        dolMap.originalFileDataOffset[i] = segments.data[i].offset;
        dolMap.header.dataAddress[i] = segments.data[i].address;
        dolMap.header.dataSize[i] = segments.data[i].size;

        // Get next aligned position
        currentPosition = std.mem.alignForward(u32, currentPosition + dolMap.header.dataSize[i], DOLAlignment);
    }

    return dolMap;
}

pub fn writeDOL(map: DolMap, input: std.fs.File, output: std.fs.File) !void {
    const reader = input.reader();
    const writer = output.writer();

    // Write header
    try oldzig.writeStructEndian(writer, map.header, std.builtin.Endian.big);

    // Create buffer for pump
    var fifo = std.fifo.LinearFifo(u8, .{ .Static = 1024 * 1024 }).init();
    defer fifo.deinit();

    // Copy over text segments
    for (0..map.textCount) |i| {
        // Seek to text segment
        try input.seekTo(map.originalFileTextOffset[i]);

        // Create limited reader to segment size
        var limitedReader = std.io.limitedReader(reader, map.header.textSize[i]);

        // Seek to destination
        try output.seekTo(map.header.textOffsets[i]);

        // Copy segment
        std.log.debug("Copying text segment {d} at 0x{x} -> 0x{x}", .{ i, map.header.textAddress[i], map.header.textOffsets[i] });
        try fifo.pump(&limitedReader, writer);
    }

    // Copy over data segments
    for (0..map.dataCount) |i| {
        // Seek to data segment
        try input.seekTo(map.originalFileDataOffset[i]);

        // Create limited reader to segment size
        var limitedReader = std.io.limitedReader(reader, map.header.dataSize[i]);

        // Seek to destination
        try output.seekTo(map.header.dataOffsets[i]);

        // Copy segment
        std.log.debug("Copying data segment {d} at 0x{x} -> 0x{x}", .{ i, map.header.dataAddress[i], map.header.dataOffsets[i] });
        try fifo.pump(&limitedReader, writer);
    }
}
