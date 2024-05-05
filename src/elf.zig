const std = @import("std");
const dol = @import("dol.zig");

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

const DolHasBSS = 1;

pub const SegmentInfo = struct {
    offset: u32,
    size: u32,
    address: u32,
};

pub const ELFSegments = struct {
    entryPoint: u32,
    textCount: u4,
    text: [dol.MaximumTextSegments]SegmentInfo,
    dataCount: u4,
    data: [dol.MaximumDataSegments]SegmentInfo,
    hasBSS: bool,
    bssAddress: u32,
    bssSize: u32,
};

pub fn readELF(file: std.fs.File) !ELFSegments {
    // Create segment map
    var elfMap: ELFSegments = .{
        .entryPoint = undefined,
        .textCount = 0,
        .text = undefined,
        .dataCount = 0,
        .data = undefined,
        .hasBSS = false,
        .bssAddress = 0,
        .bssSize = 0,
    };

    // Read header
    const reader = file.reader();
    const header = try reader.readStructEndian(ELFHeader, std.builtin.Endian.big);

    try checkELFHeader(header);

    // Get entry point
    elfMap.entryPoint = header.e_entry;

    // Read program headers
    const programCount = header.e_phnum;
    const programOffset = header.e_phoff;

    // Sanity checks
    if (programCount == 0 or programOffset == 0) {
        return ELFError.MissingProgramHeader;
    }
    if (header.e_phentsize != @sizeOf(ELFProgramHeader)) {
        return ELFError.InvalidProgramHeaderEntrySize;
    }

    // Read program headers
    try file.seekTo(programOffset);

    for (0..programCount) |_| {
        const programHeader = try reader.readStructEndian(ELFProgramHeader, std.builtin.Endian.big);

        // Skip non-loadable segments
        if (programHeader.p_type != 1) {
            std.log.debug("Skipping non-loadable segment at 0x{x}", .{programHeader.p_vaddr});
            continue;
        }

        // Skip empty segments
        if (programHeader.p_memsz == 0) {
            std.log.debug("Skipping empty segment at 0x{x}", .{programHeader.p_vaddr});
            continue;
        }

        // Check if segment is readable
        if (programHeader.p_flags & PSFlags_Readable == 0) {
            std.log.debug("Warning: non-readable segment at 0x{x}", .{programHeader.p_vaddr});
        }

        // If the segment is executable, it's a TEXT segment
        if (programHeader.p_flags & PSFlags_Executable != 0) {
            // Do we have too many text segments?
            if (elfMap.textCount >= dol.MaximumTextSegments) {
                return ELFError.TooManyTextSegments;
            }

            // Check if segment is writable
            if (programHeader.p_flags & PSFlags_Writable != 0) {
                std.log.debug("Warning: segment at 0x{x} is both executable and writable", .{programHeader.p_vaddr});
            }

            // Check if segment has valid memory size
            if (programHeader.p_filesz > programHeader.p_memsz) {
                return ELFError.TextSegmentInvalidMemorySize;
            }

            // Check if there's leftover space
            if (programHeader.p_filesz < programHeader.p_memsz) {
                // Add as BSS segment of whatever is left between the file and memory sizes
                addOrExtendBSS(&elfMap, programHeader.p_paddr + programHeader.p_filesz, programHeader.p_memsz - programHeader.p_filesz);
                std.log.debug("Found bss segment (TEXT) at 0x{x}", .{programHeader.p_paddr + programHeader.p_filesz});
            }

            std.log.debug("Found text segment at 0x{x}", .{programHeader.p_vaddr});

            elfMap.text[elfMap.textCount] = .{
                .address = programHeader.p_paddr,
                .size = programHeader.p_filesz,
                .offset = programHeader.p_offset,
            };

            elfMap.textCount += 1;
        } else {
            // DATA or BSS segment

            // TODO: ????
            if (programHeader.p_filesz == 0) {
                addOrExtendBSS(&elfMap, programHeader.p_paddr, programHeader.p_memsz);
                std.log.debug("Found bss segment (DATA) at 0x{x}", .{programHeader.p_vaddr});
                continue;
            }

            // Do we have too many data segments?
            if (elfMap.dataCount >= dol.MaximumDataSegments) {
                return ELFError.TooManyDataSegments;
            }

            std.log.debug("Found data segment at 0x{x}", .{programHeader.p_vaddr});

            elfMap.data[elfMap.dataCount] = .{
                .address = programHeader.p_paddr,
                .size = programHeader.p_filesz,
                .offset = programHeader.p_offset,
            };

            elfMap.dataCount += 1;
        }
    }

    return elfMap;
}

fn addOrExtendBSS(map: *ELFSegments, addr: u32, size: u32) void {
    // If we already have a BSS segment and it lines up, extend it
    if (map.hasBSS) {
        const originalAddr = map.bssAddress;
        const originalSize = map.bssSize;
        if ((originalAddr + originalSize) == addr) {
            map.bssSize = originalSize + size;
        }
        return;
    }

    map.bssAddress = addr;
    map.bssSize = size;
    map.hasBSS = true;
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

test "readELF: parses known .elf" {
    const input = try std.fs.cwd().openFile("testdata/example.elf", .{});
    defer input.close();

    const map = try readELF(input);
    try std.testing.expectEqual(0x80003100, map.entryPoint);
    try std.testing.expectEqual(1, map.textCount);
    try std.testing.expectEqual(1, map.dataCount);
    try std.testing.expectEqual(0x80003100, map.text[0].address);
    try std.testing.expectEqual(0x2DD0, map.text[0].size);
    try std.testing.expectEqual(0x3100, map.text[0].offset);
    try std.testing.expectEqual(0x80005ed0, map.data[0].address);
    try std.testing.expectEqual(0xD0, map.data[0].size);
    try std.testing.expectEqual(0x5ed0, map.data[0].offset);
    try std.testing.expectEqual(true, map.hasBSS);
    try std.testing.expectEqual(0x80005fa0, map.bssAddress);
    try std.testing.expectEqual(0x160, map.bssSize);
}
