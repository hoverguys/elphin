const std = @import("std");
const elf = @import("elf.zig");

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
            .textOffsets = @splat(0),
            .dataOffsets = @splat(0),
            .textAddress = @splat(0),
            .dataAddress = @splat(0),
            .textSize = @splat(0),
            .dataSize = @splat(0),
            .BSSAddress = segments.bssAddress,
            .BSSSize = segments.bssSize,
            .entrypoint = segments.entryPoint,
            .reserved = @splat(0),
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

pub fn writeDOL(map: DolMap, reader: *std.fs.File.Reader, writer: *std.fs.File.Writer, verbose: bool) !void {
    // Write header
    try writer.interface.writeStruct(map.header, .big);

    // Copy over text segments
    for (0..map.textCount) |i| {
        const segmentSize = map.header.textSize[i];
        const source_offset = map.originalFileTextOffset[i];
        const destination_offset = map.header.textOffsets[i];

        // Seek to text segment
        try reader.seekTo(source_offset);

        // Seek to destination
        try writer.seekTo(destination_offset);

        // Copy segment
        if (verbose) {
            std.log.debug("Copying text segment {d} at 0x{x} -> 0x{x}, size {d}", .{ i, map.header.textAddress[i], destination_offset, segmentSize });
        }

        try reader.interface.streamExact(&writer.interface, segmentSize);
    }

    // Copy over data segments
    for (0..map.dataCount) |i| {
        const segmentSize = map.header.dataSize[i];
        const source_offset = map.originalFileDataOffset[i];
        const destination_offset = map.header.dataOffsets[i];

        // Seek to data segment
        try reader.seekTo(source_offset);

        // Seek to destination
        try writer.seekTo(destination_offset);

        // Copy segment
        if (verbose) {
            std.log.debug("Copying data segment {d} at 0x{x} -> 0x{x}, size {d}", .{ i, map.header.dataAddress[i], destination_offset, segmentSize });
        }

        try reader.interface.streamExact(&writer.interface, segmentSize);
    }
}
