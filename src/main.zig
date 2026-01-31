const std = @import("std");

const zstd = @cImport({
    @cInclude("zstd.h");
});

const Mode = enum {
    compress,
    decompress,
};

pub const Options = struct {
    mode: Mode,
    input_path: []const u8,
    output_path: []const u8,
    level: i32 = 19,
    progress: bool = false,
    chunk_size: ?usize = null,
    threads: ?u32 = null,
    window_log: ?u32 = null,
    checksum: bool = false,
    rsyncable: bool = false,
    long_distance: bool = false,
    timing: bool = true,
};

const CliError = error{
    InvalidArgs,
    ZstdError,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const opts = try parseArgs(allocator);
    defer allocator.free(opts.input_path);
    defer allocator.free(opts.output_path);

    switch (opts.mode) {
        .compress => try compressFile(allocator, opts),
        .decompress => try decompressFile(allocator, opts),
    }
}

fn parseArgs(allocator: std.mem.Allocator) !Options {
    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();
    _ = args_it.next();

    const mode_arg = args_it.next() orelse {
        printUsage();
        return CliError.InvalidArgs;
    };

    const mode: Mode = if (std.mem.eql(u8, mode_arg, "compress"))
        .compress
    else if (std.mem.eql(u8, mode_arg, "decompress"))
        .decompress
    else {
        printUsage();
        return CliError.InvalidArgs;
    };

    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var level: i32 = 19;
    var progress = false;
    var chunk_size: ?usize = null;
    var threads: ?u32 = null;
    var max_threads = false;
    var window_log: ?u32 = null;
    var checksum = false;
    var rsyncable = false;
    var long_distance = false;
    var timing = true;

    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
            const value = args_it.next() orelse return CliError.InvalidArgs;
            input_path = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            const value = args_it.next() orelse return CliError.InvalidArgs;
            output_path = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--level")) {
            const value = args_it.next() orelse return CliError.InvalidArgs;
            level = try std.fmt.parseInt(i32, value, 10);
        } else if (std.mem.eql(u8, arg, "--progress")) {
            progress = true;
        } else if (std.mem.eql(u8, arg, "--chunk-size")) {
            const value = args_it.next() orelse return CliError.InvalidArgs;
            chunk_size = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, arg, "--threads")) {
            const value = args_it.next() orelse return CliError.InvalidArgs;
            if (std.mem.eql(u8, value, "max")) {
                max_threads = true;
            } else {
                threads = try std.fmt.parseInt(u32, value, 10);
            }
        } else if (std.mem.eql(u8, arg, "--threads=max")) {
            max_threads = true;
        } else if (std.mem.eql(u8, arg, "--window-log")) {
            const value = args_it.next() orelse return CliError.InvalidArgs;
            window_log = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, arg, "--checksum")) {
            checksum = true;
        } else if (std.mem.eql(u8, arg, "--rsyncable")) {
            rsyncable = true;
        } else if (std.mem.eql(u8, arg, "--long-distance")) {
            long_distance = true;
        } else if (std.mem.eql(u8, arg, "--no-timing")) {
            timing = false;
        } else {
            printUsage();
            return CliError.InvalidArgs;
        }
    }

    if (input_path == null or output_path == null) {
        printUsage();
        return CliError.InvalidArgs;
    }

    return Options{
        .mode = mode,
        .input_path = input_path.?,
        .output_path = output_path.?,
        .level = level,
        .progress = progress,
        .chunk_size = chunk_size,
        .threads = if (max_threads) getCpuCount() else threads,
        .window_log = window_log,
        .checksum = checksum,
        .rsyncable = rsyncable,
        .long_distance = long_distance,
        .timing = timing,
    };
}

fn printUsage() void {
    const stderr = std.io.getStdErr().writer();
    _ = stderr.write(
        "Usage:\n" ++
            "  zig-zstd compress -i <input> -o <output> [-l <level>] [--progress] [--chunk-size <bytes>] [--threads <n>|--threads=max] [--window-log <n>] [--checksum] [--rsyncable] [--long-distance] [--no-timing]\n" ++
            "  zig-zstd decompress -i <input> -o <output> [--progress] [--chunk-size <bytes>] [--no-timing]\n" ++
            "\n" ++
            "Notes:\n" ++
            "  - Default compression level is 19\n" ++
            "  - --progress prints periodic progress updates\n" ++
            "  - timing output is enabled by default (use --no-timing to disable)\n",
    ) catch {};
}

pub fn compressFile(allocator: std.mem.Allocator, opts: Options) !void {
    const start_ns = std.time.nanoTimestamp();
    var input_file = try std.fs.cwd().openFile(opts.input_path, .{});
    defer input_file.close();

    var output_file = try std.fs.cwd().createFile(opts.output_path, .{ .truncate = true });
    defer output_file.close();

    const in_chunk = opts.chunk_size orelse zstd.ZSTD_CStreamInSize();
    const out_chunk = zstd.ZSTD_CStreamOutSize();

    const in_buf = try allocator.alloc(u8, in_chunk);
    defer allocator.free(in_buf);

    var out_buf = try allocator.alloc(u8, out_chunk);
    defer allocator.free(out_buf);

    const cstream = zstd.ZSTD_createCStream();
    if (cstream == null) return CliError.ZstdError;
    defer _ = zstd.ZSTD_freeCStream(cstream);

    const init_res = zstd.ZSTD_initCStream(cstream, opts.level);
    try zstdCheck(init_res);

    if (opts.threads) |threads| {
        setParam(
            cstream.?,
            zstd.ZSTD_c_nbWorkers,
            @as(i32, @intCast(threads)),
            "threads",
        );
    }
    if (opts.window_log) |window_log| {
        setParam(
            cstream.?,
            zstd.ZSTD_c_windowLog,
            @as(i32, @intCast(window_log)),
            "window-log",
        );
    }
    if (opts.checksum) {
        setParam(cstream.?, zstd.ZSTD_c_checksumFlag, 1, "checksum");
    }
    if (opts.rsyncable) {
        if (@hasDecl(zstd, "ZSTD_c_rsyncable")) {
            setParam(cstream.?, zstd.ZSTD_c_rsyncable, 1, "rsyncable");
        } else {
            const stderr = std.io.getStdErr().writer();
            _ = stderr.write("Warning: zstd does not support rsyncable on this version\n") catch {};
        }
    }
    if (opts.long_distance) {
        setParam(
            cstream.?,
            zstd.ZSTD_c_enableLongDistanceMatching,
            1,
            "long-distance",
        );
    }

    const total_size = getFileSize(input_file);
    var processed: u64 = 0;
    var last_log_ms: i64 = std.time.milliTimestamp();

    while (true) {
        const bytes_read = try input_file.read(in_buf);
        if (bytes_read == 0) break;

        processed += bytes_read;

        var input = zstd.ZSTD_inBuffer{ .src = in_buf.ptr, .size = bytes_read, .pos = 0 };
        while (input.pos < input.size) {
            var output = zstd.ZSTD_outBuffer{ .dst = out_buf.ptr, .size = out_buf.len, .pos = 0 };
            const res = zstd.ZSTD_compressStream2(cstream, &output, &input, zstd.ZSTD_e_continue);
            try zstdCheck(res);
            try output_file.writeAll(out_buf[0..output.pos]);
        }

        if (opts.progress) {
            logProgress("Compressing", processed, total_size, &last_log_ms);
        }
    }

    var empty_input = zstd.ZSTD_inBuffer{ .src = null, .size = 0, .pos = 0 };
    while (true) {
        var output = zstd.ZSTD_outBuffer{ .dst = out_buf.ptr, .size = out_buf.len, .pos = 0 };
        const res = zstd.ZSTD_compressStream2(cstream, &output, &empty_input, zstd.ZSTD_e_end);
        try zstdCheck(res);
        if (output.pos > 0) {
            try output_file.writeAll(out_buf[0..output.pos]);
        }
        if (res == 0) break;
    }

    if (opts.timing) {
        const end_ns = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_ns - start_ns)) / 1_000_000.0;
        const stderr = std.io.getStdErr().writer();
        _ = stderr.print("Compression time: {d:.2} ms\n", .{duration_ms}) catch {};
    }
}

pub fn decompressFile(allocator: std.mem.Allocator, opts: Options) !void {
    const start_ns = std.time.nanoTimestamp();
    var input_file = try std.fs.cwd().openFile(opts.input_path, .{});
    defer input_file.close();

    var output_file = try std.fs.cwd().createFile(opts.output_path, .{ .truncate = true });
    defer output_file.close();

    const in_chunk = opts.chunk_size orelse zstd.ZSTD_DStreamInSize();
    const out_chunk = zstd.ZSTD_DStreamOutSize();

    const in_buf = try allocator.alloc(u8, in_chunk);
    defer allocator.free(in_buf);

    var out_buf = try allocator.alloc(u8, out_chunk);
    defer allocator.free(out_buf);

    const dstream = zstd.ZSTD_createDStream();
    if (dstream == null) return CliError.ZstdError;
    defer _ = zstd.ZSTD_freeDStream(dstream);

    const init_res = zstd.ZSTD_initDStream(dstream);
    try zstdCheck(init_res);

    const total_size = getFileSize(input_file);
    var processed: u64 = 0;
    var last_log_ms: i64 = std.time.milliTimestamp();

    while (true) {
        const bytes_read = try input_file.read(in_buf);
        if (bytes_read == 0) break;

        processed += bytes_read;

        var input = zstd.ZSTD_inBuffer{ .src = in_buf.ptr, .size = bytes_read, .pos = 0 };
        while (input.pos < input.size) {
            var output = zstd.ZSTD_outBuffer{ .dst = out_buf.ptr, .size = out_buf.len, .pos = 0 };
            const res = zstd.ZSTD_decompressStream(dstream, &output, &input);
            try zstdCheck(res);
            if (output.pos > 0) {
                try output_file.writeAll(out_buf[0..output.pos]);
            }
        }

        if (opts.progress) {
            logProgress("Decompressing", processed, total_size, &last_log_ms);
        }
    }

    if (opts.timing) {
        const end_ns = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_ns - start_ns)) / 1_000_000.0;
        const stderr = std.io.getStdErr().writer();
        _ = stderr.print("Decompression time: {d:.2} ms\n", .{duration_ms}) catch {};
    }
}

fn getFileSize(file: std.fs.File) ?u64 {
    const stat = file.stat() catch return null;
    return stat.size;
}

fn logProgress(label: []const u8, processed: u64, total: ?u64, last_log_ms: *i64) void {
    const now = std.time.milliTimestamp();
    if (now - last_log_ms.* < 5000) return;
    last_log_ms.* = now;

    const stderr = std.io.getStdErr().writer();
    if (total) |t| {
        const percent = if (t == 0) 0 else @as(u64, processed * 100 / t);
        _ = stderr.print("{s}: {d}/{d} ({d}%)\n", .{ label, processed, t, percent }) catch {};
    } else {
        _ = stderr.print("{s}: {d} bytes\n", .{ label, processed }) catch {};
    }
}

fn zstdCheck(code: usize) !void {
    if (zstd.ZSTD_isError(code) != 0) {
        return CliError.ZstdError;
    }
}

fn getCpuCount() ?u32 {
    const count = std.Thread.getCpuCount() catch return null;
    return @as(u32, @intCast(count));
}

fn setParam(cstream: *zstd.ZSTD_CCtx, param: c_uint, value: i32, name: []const u8) void {
    const result = zstd.ZSTD_CCtx_setParameter(cstream, param, value);
    if (zstd.ZSTD_isError(result) != 0) {
        const stderr = std.io.getStdErr().writer();
        _ = stderr.print("Warning: failed to set {s} (error code {d})\n", .{ name, result }) catch {};
    }
}
