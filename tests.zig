const std = @import("std");
const zstd_cli = @import("src/main.zig");

fn writeRandomFile(io: std.Io, file: std.Io.File, size: usize) !void {
    var prng = std.Random.DefaultPrng.init(0x12345678);
    var random = prng.random();

    const buf = try std.heap.page_allocator.alloc(u8, size);
    defer std.heap.page_allocator.free(buf);

    random.bytes(buf);
    try file.writeStreamingAll(io, buf);
}

test "compress and decompress roundtrip" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(tmp_root);

    const input_path = try std.fs.path.join(allocator, &.{ tmp_root, "input.bin" });
    defer allocator.free(input_path);

    const compressed_path = try std.fs.path.join(allocator, &.{ tmp_root, "output.zst" });
    defer allocator.free(compressed_path);

    const decompressed_path = try std.fs.path.join(allocator, &.{ tmp_root, "output.bin" });
    defer allocator.free(decompressed_path);

    {
        var input_file = try tmp.dir.createFile(io, "input.bin", .{ .truncate = true });
        defer input_file.close(io);
        try writeRandomFile(io, input_file, 256 * 1024);
    }

    try zstd_cli.compressFile(allocator, io, .{
        .mode = .compress,
        .input_path = input_path,
        .output_path = compressed_path,
        .level = 10,
        .progress = false,
        .chunk_size = 64 * 1024,
        .timing = false,
    });

    try zstd_cli.decompressFile(allocator, io, .{
        .mode = .decompress,
        .input_path = compressed_path,
        .output_path = decompressed_path,
        .progress = false,
        .chunk_size = 64 * 1024,
        .timing = false,
    });

    const original_bytes = try tmp.dir.readFileAlloc(io, "input.bin", allocator, .limited(10 * 1024 * 1024));
    defer allocator.free(original_bytes);

    const restored_bytes = try tmp.dir.readFileAlloc(io, "output.bin", allocator, .limited(10 * 1024 * 1024));
    defer allocator.free(restored_bytes);

    try std.testing.expectEqualSlices(u8, original_bytes, restored_bytes);
}

fn roundtrip(allocator: std.mem.Allocator, io: std.Io, tmp: *std.testing.TmpDir, data: []const u8, chunk_size: ?usize) !u64 {
    const tmp_root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(tmp_root);

    const input_path = try std.fs.path.join(allocator, &.{ tmp_root, "rt-input.bin" });
    defer allocator.free(input_path);

    const compressed_path = try std.fs.path.join(allocator, &.{ tmp_root, "rt-output.zst" });
    defer allocator.free(compressed_path);

    const decompressed_path = try std.fs.path.join(allocator, &.{ tmp_root, "rt-output.bin" });
    defer allocator.free(decompressed_path);

    try tmp.dir.writeFile(io, .{ .sub_path = "rt-input.bin", .data = data });

    try zstd_cli.compressFile(allocator, io, .{
        .mode = .compress,
        .input_path = input_path,
        .output_path = compressed_path,
        .level = 3,
        .chunk_size = chunk_size,
        .timing = false,
    });

    try zstd_cli.decompressFile(allocator, io, .{
        .mode = .decompress,
        .input_path = compressed_path,
        .output_path = decompressed_path,
        .chunk_size = chunk_size,
        .timing = false,
    });

    const restored = try tmp.dir.readFileAlloc(io, "rt-output.bin", allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(restored);
    try std.testing.expectEqualSlices(u8, data, restored);

    var compressed_file = try tmp.dir.openFile(io, "rt-output.zst", .{});
    defer compressed_file.close(io);
    const stat = try compressed_file.stat(io);
    return stat.size;
}

test "streaming roundtrip shrinks compressible data" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const data = try allocator.alloc(u8, 512 * 1024);
    defer allocator.free(data);
    for (data, 0..) |*byte, i| {
        byte.* = @truncate((i / 1024) % 251);
    }

    // Chunk size smaller than the payload forces multiple streaming iterations.
    const compressed_size = try roundtrip(allocator, io, &tmp, data, 32 * 1024);
    try std.testing.expect(compressed_size < data.len / 4);
}

test "empty input roundtrip" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const compressed_size = try roundtrip(allocator, io, &tmp, &.{}, null);
    // An empty zstd frame still has a header.
    try std.testing.expect(compressed_size > 0);
}
