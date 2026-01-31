const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libzstd = b.addStaticLibrary(.{
        .name = "zstd",
        .target = target,
        .optimize = optimize,
    });

    // Disable assembly optimizations to avoid linking issues with missing HUF assembly functions
    libzstd.defineCMacro("ZSTD_DISABLE_ASM", "1");
    // Enable multithreaded compression when available
    libzstd.defineCMacro("ZSTD_MULTITHREAD", "1");

    libzstd.addCSourceFiles(.{
        .files = &[_][]const u8{
            "zstd/lib/common/debug.c",
            "zstd/lib/common/entropy_common.c",
            "zstd/lib/common/error_private.c",
            "zstd/lib/common/fse_decompress.c",
            "zstd/lib/common/pool.c",
            "zstd/lib/common/threading.c",
            "zstd/lib/common/xxhash.c",
            "zstd/lib/common/zstd_common.c",

            "zstd/lib/compress/fse_compress.c",
            "zstd/lib/compress/hist.c",
            "zstd/lib/compress/huf_compress.c",
            "zstd/lib/compress/zstd_compress_literals.c",
            "zstd/lib/compress/zstd_compress_sequences.c",
            "zstd/lib/compress/zstd_compress_superblock.c",
            "zstd/lib/compress/zstd_compress.c",
            "zstd/lib/compress/zstd_double_fast.c",
            "zstd/lib/compress/zstd_fast.c",
            "zstd/lib/compress/zstd_lazy.c",
            "zstd/lib/compress/zstd_ldm.c",
            "zstd/lib/compress/zstd_opt.c",
            "zstd/lib/compress/zstd_preSplit.c",
            "zstd/lib/compress/zstdmt_compress.c",

            "zstd/lib/decompress/zstd_decompress.c",
            "zstd/lib/decompress/zstd_ddict.c",
            "zstd/lib/decompress/zstd_decompress_block.c",
            "zstd/lib/decompress/huf_decompress.c",
        },
    });

    libzstd.linkLibC();

    const exe = b.addExecutable(.{
        .name = "zig-zstd",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(libzstd);
    exe.addIncludePath(b.path("zstd/lib"));
    if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("pthread");
    }

    b.installArtifact(exe);

    const tests = b.addTest(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    tests.addIncludePath(b.path("zstd/lib"));
    tests.linkLibrary(libzstd);
    if (target.result.os.tag == .linux) {
        tests.linkSystemLibrary("pthread");
    }

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run zig-zstd tests");
    test_step.dependOn(&run_tests.step);
}
