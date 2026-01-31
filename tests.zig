const std = @import("std");
const zstd_cli = @import("src/main.zig");

fn writeRandomFile(file: std.fs.File, size: usize) !void {
    var prng = std.rand.DefaultPrng.init(0x12345678);
    var random = prng.random();

    const buf = try std.heap.page_allocator.alloc(u8, size);
    defer std.heap.page_allocator.free(buf);

    random.bytes(buf);
    try file.writeAll(buf);
}

test "compress and decompress roundtrip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_root);

    const input_path = try std.fs.path.join(allocator, &.{ tmp_root, "input.bin" });
    defer allocator.free(input_path);

    const compressed_path = try std.fs.path.join(allocator, &.{ tmp_root, "output.zst" });
    defer allocator.free(compressed_path);

    const decompressed_path = try std.fs.path.join(allocator, &.{ tmp_root, "output.bin" });
    defer allocator.free(decompressed_path);

    {
        var input_file = try tmp.dir.createFile("input.bin", .{ .truncate = true });
        defer input_file.close();
        try writeRandomFile(input_file, 256 * 1024);
    }

    try zstd_cli.compressFile(allocator, .{
        .mode = .compress,
        .input_path = input_path,
        .output_path = compressed_path,
        .level = 10,
        .progress = false,
        .chunk_size = 64 * 1024,
        .timing = false,
    });

    try zstd_cli.decompressFile(allocator, .{
        .mode = .decompress,
        .input_path = compressed_path,
        .output_path = decompressed_path,
        .progress = false,
        .chunk_size = 64 * 1024,
        .timing = false,
    });

    const original = try tmp.dir.openFile("input.bin", .{});
    defer original.close();
    const restored = try tmp.dir.openFile("output.bin", .{});
    defer restored.close();

    const original_bytes = try original.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(original_bytes);

    const restored_bytes = try restored.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(restored_bytes);

    try std.testing.expectEqualSlices(u8, original_bytes, restored_bytes);
}
