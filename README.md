# zig-zstd

A tiny zstd CLI built in Zig with a static libzstd.

## Build

```bash
zig build
```

## Usage

```bash
./zig-out/bin/zig-zstd compress -i input.tar -o input.tar.zst -l 19 --progress --threads 4 --checksum
./zig-out/bin/zig-zstd decompress -i input.tar.zst -o input.tar
```

Options:
- `-i`, `--input`: input file path (required)
- `-o`, `--output`: output file path (required)
- `-l`, `--level`: compression level (default: 19)
- `--progress`: print periodic progress updates
- `--chunk-size`: override streaming chunk size (bytes)
- `--threads`: number of worker threads for compression (`--threads=max` uses CPU count)
- `--window-log`: set compression window log (affects memory usage)
- `--checksum`: include a checksum in the zstd frame
- `--rsyncable`: generate rsync-friendly output (lower ratio, higher CPU)
- `--long-distance`: enable long distance matching for better ratios on large files
- `--no-timing`: disable timing output

Notes:
- `--threads` requires zstd built with multithread support; a warning is printed if the option isn't applied.

## Tests

```bash
zig build test
```

## Integration test

```bash
bun dev
bun dev 200
```

The optional numeric argument is the size (in MB) for the tar payload.
