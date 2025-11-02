const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("elphin", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "elphin",
        .root_module = module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Testing
    const elf_unit_tests = b.addTest(.{
        .root_module = b.addModule("elphin", .{
            .root_source_file = b.path("src/elf.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_elf_unit_tests = b.addRunArtifact(elf_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_elf_unit_tests.step);
}
