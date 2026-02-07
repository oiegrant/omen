const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Pull pg.zig from build.zig.zon
    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "ingest-polymarkets",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./src/zig/ingest-polymarket.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Make `@import("pg")` work
    exe.root_module.addImport("pg", pg.module("pg"));

    b.installArtifact(exe);

    // Optional: zig build run
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run ingest-polymarkets");
    run_step.dependOn(&run_cmd.step);
}
