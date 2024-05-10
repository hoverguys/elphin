const elf = @import("elf.zig");
const dol = @import("dol.zig");

pub const ELFError = elf.ELFError;
pub const ELFSegments = elf.ELFSegments;

pub const readELF = elf.readELF;
pub const createDOLMapping = dol.createDOLMapping;
pub const writeDOL = dol.writeDOL;

/// Converts an ELF file to a DOL file.
/// `input` and `output` must be open files.
pub fn convert(input: anytype, output: anytype) !void {
    // Read input
    const map = try elf.readELF(input);

    // Align segments to 64 byte boundaries
    const dolMap = dol.createDOLMapping(map);

    // Write header and copy over segments from input
    try dol.writeDOL(dolMap, input, output);
}
