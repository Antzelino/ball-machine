const std = @import("std");

fn setupWasmtime(b: *std.Build, opt: std.builtin.OptimizeMode) !std.Build.LazyPath {
    const tool_run = b.addSystemCommand(&.{"cargo"});
    tool_run.setCwd(b.path("deps/wasmtime/crates/c-api/artifact/"));
    tool_run.addArgs(&.{ "build", "--no-default-features" });

    var opt_path: []const u8 = undefined;
    switch (opt) {
        .ReleaseSafe,
        .ReleaseFast,
        .ReleaseSmall,
        => {
            tool_run.addArg("--release");
            opt_path = "release";
        },
        .Debug => {
            opt_path = "debug";
        },
    }

    const generated = try b.allocator.create(std.Build.GeneratedFile);
    generated.* = .{
        .step = &tool_run.step,
        .path = try b.build_root.join(b.allocator, &.{ "deps/wasmtime/target", opt_path, "libwasmtime.a" }),
    };

    const lib_path = std.Build.LazyPath{ .generated = .{
        .file = generated,
    } };

    return lib_path;
}

pub fn buildChamber(b: *std.Build, name: []const u8, opt: std.builtin.OptimizeMode) !void {
    const path = try std.fmt.allocPrint(b.allocator, "src/chambers/{s}.zig", .{name});
    const chamber = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(path),
        .target = b.resolveTargetQuery(std.zig.CrossTarget.parse(
            .{ .arch_os_abi = "wasm32-freestanding" },
        ) catch unreachable),
        .optimize = opt,
    });
    chamber.root_module.addAnonymousImport("physics", .{ .root_source_file = b.path("src/physics.zig") });
    chamber.entry = .disabled;
    chamber.rdynamic = true;
    b.installArtifact(chamber);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});

    const generate_embedded_resources = b.addExecutable(.{
        .name = "generate_embedded_resources",
        .root_source_file = b.path("tools/generate_embedded_resources.zig"),
        .target = b.host,
    });

    try buildChamber(b, "simple", opt);
    try buildChamber(b, "platforms", opt);

    const generate_embedded_resources_step = b.addRunArtifact(generate_embedded_resources);
    const output = generate_embedded_resources_step.addOutputFileArg("resources.zig");
    _ = generate_embedded_resources_step.addDepFileOutputArg("deps.d");
    generate_embedded_resources_step.addDirectoryArg(b.path("src/res"));

    const wasmtime_lib = try setupWasmtime(b, opt);

    const exe = b.addExecutable(.{
        .name = "ball-machine",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = opt,
    });
    exe.root_module.addAnonymousImport("resources", .{ .root_source_file = output });
    exe.addLibraryPath(wasmtime_lib.dirname());
    const link_mode: std.builtin.LinkMode = switch (opt) {
        // dynamic is faster, but harder to ship
        .Debug => .dynamic,
        else => .static,
    };
    exe.root_module.linkSystemLibrary("wasmtime", .{
        .preferred_link_mode = link_mode,
    });
    exe.addIncludePath(b.path("deps/wasmtime/crates/c-api/include"));
    exe.linkLibC();
    exe.linkLibCpp();
    b.installArtifact(exe);

    const userinfo = b.addExecutable(.{
        .name = "userinfo",
        .root_source_file = b.path("src/userinfo.zig"),
        .target = target,
        .optimize = opt,
    });
    userinfo.linkSystemLibrary("ssl");
    userinfo.linkSystemLibrary("crypto");
    userinfo.linkLibC();
    b.installArtifact(userinfo);
}
