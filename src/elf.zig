const std = @import("std");
const oldzig = @import("oldzig.zig");

// Cool website for ELF info:
// https://www.man7.org/linux/man-pages/man5/elf.5.html

pub const ELFError = error{
    InvalidMagic,
    InvalidClass,
    InvalidByteOrder,
    InvalidIdentVersion,
    InvalidVersion,
    NotExecutable,
    NotPowerPC,
    NoEntrypoint,
    MissingProgramHeader,
    InvalidProgramHeaderEntrySize,
    TextSegmentInvalidMemorySize,
    TooManyTextSegments,
    TooManyDataSegments,
};

const ELFMagic = "\x7fELF";
const ELFClass_32bit = 1;
const ELFDataFormat_BigEndian = 2;
const ELFVersion_Current = 1;
const ELFType_Executable = 2;
const ELFMachine_PowerPC = 20;

const MaximumTextSegments = 7;
const MaximumDataSegments = 11;

const PSFlags_Executable = 1;
const PSFlags_Writable = 2;
const PSFlags_Readable = 4;

const ELFHeader = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u32,
    e_phoff: u32,
    e_shoff: u32,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

const ELFProgramHeader = extern struct {
    p_type: u32,
    p_offset: u32,
    p_vaddr: u32,
    p_paddr: u32,
    p_filesz: u32,
    p_memsz: u32,
    p_flags: u32,
    p_align: u32,
};

pub const DolHeader = extern struct {
    text_off: [7]u32,
    data_off: [11]u32,
    text_addr: [7]u32,
    data_addr: [11]u32,
    text_size: [7]u32,
    data_size: [11]u32,
    bss_addr: u32,
    bss_size: u32,
    entry: u32,
    pad: [7]u32,
};

pub const DolMap = struct {
    header: DolHeader,
    text_cnt: u32,
    data_cnt: u32,
    text_elf_off: [7]u32,
    data_elf_off: [11]u32,
    flags: u32,
};

const DolHasBSS = 1;

pub fn readELF(file: std.fs.File) !DolMap {

    // Create dol map
    var dolMap = DolMap{
        .header = .{
            .text_off = .{0} ** 7,
            .data_off = .{0} ** 11,
            .text_addr = .{0} ** 7,
            .data_addr = .{0} ** 11,
            .text_size = .{0} ** 7,
            .data_size = .{0} ** 11,
            .bss_addr = 0,
            .bss_size = 0,
            .entry = 0,
            .pad = .{0} ** 7,
        },
        .text_cnt = 0,
        .data_cnt = 0,
        .text_elf_off = undefined,
        .data_elf_off = undefined,
        .flags = 0,
    };

    // Read header
    const reader = file.reader();
    const header = try reader.readStructEndian(ELFHeader, std.builtin.Endian.big);

    try checkELFHeader(header);

    // Get entry point
    dolMap.header.entry = header.e_entry;

    // Read program headers
    const phnum = header.e_phnum;
    const phoff = header.e_phoff;

    // Sanity checks
    if (phnum == 0 or phoff == 0) {
        return ELFError.MissingProgramHeader;
    }
    if (header.e_phentsize != @sizeOf(ELFProgramHeader)) {
        return ELFError.InvalidProgramHeaderEntrySize;
    }

    // Read program headers
    try file.seekTo(phoff);

    for (0..phnum) |_| {
        const programHeader = try reader.readStructEndian(ELFProgramHeader, std.builtin.Endian.big);

        // Skip non-loadable segments
        if (programHeader.p_type != 1) {
            std.debug.print("Skipping non-loadable segment at 0x{x}\n", .{programHeader.p_vaddr});
            continue;
        }

        // Skip empty segments
        if (programHeader.p_memsz == 0) {
            std.debug.print("Skipping empty segment at 0x{x}\n", .{programHeader.p_vaddr});
            continue;
        }

        // Check if segment is readable
        if (programHeader.p_flags & PSFlags_Readable == 0) {
            std.debug.print("Warning: non-readable segment at 0x{x}\n", .{programHeader.p_vaddr});
        }

        // If the segment is executable, it's a TEXT segment
        if (programHeader.p_flags & PSFlags_Executable != 0) {
            // Do we have too many text segments?
            if (dolMap.text_cnt >= MaximumTextSegments) {
                return ELFError.TooManyTextSegments;
            }

            // Check if segment is writable
            if (programHeader.p_flags & PSFlags_Writable != 0) {
                std.debug.print("Warning: segment at 0x{x} is both executable and writable\n", .{programHeader.p_vaddr});
            }

            // Check if segment has valid memory size
            if (programHeader.p_filesz > programHeader.p_memsz) {
                return ELFError.TextSegmentInvalidMemorySize;
            }

            // Check if there's leftover space
            if (programHeader.p_filesz < programHeader.p_memsz) {
                // Add as BSS segment of whatever is left between the file and memory sizes
                // TODO: why?!
                add_bss(&dolMap, programHeader.p_paddr + programHeader.p_filesz, programHeader.p_memsz - programHeader.p_filesz);
                std.debug.print("Found bss segment (TEXT) at 0x{x}\n", .{programHeader.p_paddr + programHeader.p_filesz});
            }

            std.debug.print("Found text segment at 0x{x}\n", .{programHeader.p_vaddr});

            dolMap.header.text_addr[dolMap.text_cnt] = programHeader.p_paddr;
            dolMap.header.text_size[dolMap.text_cnt] = programHeader.p_filesz;
            dolMap.text_elf_off[dolMap.text_cnt] = programHeader.p_offset;

            dolMap.text_cnt += 1;
        } else {
            // DATA or BSS segment

            // TODO: ????
            if (programHeader.p_filesz == 0) {
                add_bss(&dolMap, programHeader.p_paddr, programHeader.p_memsz);
                std.debug.print("Found bss segment (DATA) at 0x{x}\n", .{programHeader.p_vaddr});
                continue;
            }

            // Do we have too many data segments?
            if (dolMap.data_cnt >= MaximumDataSegments) {
                return ELFError.TooManyDataSegments;
            }

            std.debug.print("Found data segment at 0x{x}\n", .{programHeader.p_vaddr});

            dolMap.header.data_addr[dolMap.data_cnt] = programHeader.p_paddr;
            dolMap.header.data_size[dolMap.data_cnt] = programHeader.p_filesz;
            dolMap.data_elf_off[dolMap.data_cnt] = programHeader.p_offset;

            dolMap.data_cnt += 1;
        }
    }

    return dolMap;
}

// I don't understand what this does
fn add_bss(map: *DolMap, addr: u32, size: u32) void {
    if (map.flags & DolHasBSS != 0) {
        const originalAddr = map.header.bss_addr;
        const originalSize = map.header.bss_size;
        if ((originalAddr + originalSize) == addr) {
            map.header.bss_size = originalSize + size;
        }
    } else {
        map.header.bss_addr = addr;
        map.header.bss_size = size;
        map.flags |= DolHasBSS;
    }
}

const DOLAlignment = 64;
pub fn alignSegments(map: *DolMap) void {
    std.debug.print("Mapping DOL to 64 byte alignment\n", .{});
    var currentPosition = std.mem.alignForward(u32, @sizeOf(DolHeader), DOLAlignment);

    for (0..map.text_cnt) |i| {
        std.debug.print(" - Mapping text segment {d} at 0x{x} -> 0x{x}\n", .{ i, map.header.text_addr[i], currentPosition });
        map.header.text_off[i] = currentPosition;
        currentPosition = std.mem.alignForward(u32, currentPosition + map.header.text_size[i], DOLAlignment);
    }

    for (0..map.data_cnt) |i| {
        std.debug.print(" - Mapping data segment {d} at 0x{x} -> 0x{x}\n", .{ i, map.header.data_addr[i], currentPosition });
        map.header.data_off[i] = currentPosition;
        currentPosition = std.mem.alignForward(u32, currentPosition + map.header.data_size[i], DOLAlignment);
    }

    // Add dummy segments if no TEXT or DATA segments are present
    if (map.text_cnt == 0) {
        map.header.text_off[0] = std.mem.alignForward(u32, @sizeOf(DolHeader), DOLAlignment);
    }
    if (map.data_cnt == 0) {
        map.header.data_off[0] = std.mem.alignForward(u32, @sizeOf(DolHeader), DOLAlignment);
    }
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
    for (0..map.text_cnt) |i| {
        // Seek to text segment
        try input.seekTo(map.text_elf_off[i]);

        // Create limited reader to segment size
        var limitedReader = std.io.limitedReader(reader, map.header.text_size[i]);

        // Seek to destination
        try output.seekTo(map.header.text_off[i]);

        // Copy segment
        std.debug.print("Copying text segment {d} at 0x{x} -> 0x{x}\n", .{ i, map.header.text_addr[i], map.header.text_off[i] });
        try fifo.pump(&limitedReader, writer);
    }

    // Copy over data segments
    for (0..map.data_cnt) |i| {
        // Seek to data segment
        try input.seekTo(map.data_elf_off[i]);

        // Create limited reader to segment size
        var limitedReader = std.io.limitedReader(reader, map.header.data_size[i]);

        // Seek to destination
        try output.seekTo(map.header.data_off[i]);

        // Copy segment
        std.debug.print("Copying data segment {d} at 0x{x} -> 0x{x}\n", .{ i, map.header.data_addr[i], map.header.data_off[i] });
        try fifo.pump(&limitedReader, writer);
    }
}

fn checkELFHeader(header: ELFHeader) !void {
    // Check magic
    if (!std.mem.eql(u8, header.e_ident[0..4], ELFMagic)) {
        return ELFError.InvalidMagic;
    }

    // Check class
    if (header.e_ident[4] != ELFClass_32bit) {
        return ELFError.InvalidClass;
    }

    // Check byte order
    if (header.e_ident[5] != ELFDataFormat_BigEndian) {
        return ELFError.InvalidByteOrder;
    }

    // Check ident version
    if (header.e_ident[6] != ELFVersion_Current) {
        return ELFError.InvalidIdentVersion;
    }

    // Check version
    if (header.e_version != ELFVersion_Current) {
        return ELFError.InvalidVersion;
    }

    // Check type
    if (header.e_type != ELFType_Executable) {
        return ELFError.NotExecutable;
    }

    // Check machine
    if (header.e_machine != ELFMachine_PowerPC) {
        return ELFError.NotPowerPC;
    }

    // Check entry point
    if (header.e_entry == 0) {
        return ELFError.NoEntrypoint;
    }
}
