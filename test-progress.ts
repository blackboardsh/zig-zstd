import { mkdtempSync, rmSync, writeFileSync, mkdirSync, statSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

const ROOT = process.cwd();
const BIN = process.platform === "win32"
  ? join(ROOT, "zig-out", "bin", "zig-zstd.exe")
  : join(ROOT, "zig-out", "bin", "zig-zstd");

const args = process.argv.slice(2);
const sizeArg = args[0];
const TAR_SIZE_MB = sizeArg ? Number(sizeArg) : 50;
const TAR_SIZE_BYTES = TAR_SIZE_MB * 1024 * 1024;
const extraZstdArgs = args.slice(sizeArg ? 1 : 0);

async function run(cmd: string[], cwd?: string) {
  const proc = Bun.spawn({
    cmd,
    cwd,
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    throw new Error(`Command failed (${exitCode}): ${cmd.join(" ")}`);
  }
}

function formatBytes(bytes: number) {
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function createRandomFile(filePath: string, sizeBytes: number) {
  const chunk = 1024 * 1024;
  const chunks = Math.ceil(sizeBytes / chunk);
  const out = Bun.file(filePath).writer();

  for (let i = 0; i < chunks; i++) {
    const remaining = sizeBytes - i * chunk;
    const size = Math.min(chunk, remaining);
    const buf = new Uint8Array(size);
    crypto.getRandomValues(buf);
    out.write(buf);
  }
  out.end();
}

async function main() {
  if (!Number.isFinite(TAR_SIZE_MB) || TAR_SIZE_MB <= 0) {
    throw new Error(`Invalid size: ${sizeArg}`);
  }

  const tempRoot = mkdtempSync(join(tmpdir(), "zig-zstd-"));
  const dataDir = join(tempRoot, "data");
  const tarPath = join(tempRoot, "archive.tar");
  const zstPath = join(tempRoot, "archive.tar.zst");
  const restoredTarPath = join(tempRoot, "archive.restored.tar");

  try {
    mkdirSync(dataDir, { recursive: true });

    const dataPath = join(dataDir, "payload.bin");
    console.log(`Creating random payload: ${formatBytes(TAR_SIZE_BYTES)} -> ${dataPath}`);
    createRandomFile(dataPath, TAR_SIZE_BYTES);

    console.log("Creating tar using system tar...");
    await run(["tar", "-cf", tarPath, "-C", dataDir, "."]);

    const tarSize = statSync(tarPath).size;
    console.log(`Tar size: ${formatBytes(tarSize)}`);

    console.log("Compressing tar...");
    await run([BIN, "compress", "-i", tarPath, "-o", zstPath, "-l", "19", "--progress", ...extraZstdArgs]);

    const zstSize = statSync(zstPath).size;
    console.log(`Zstd size: ${formatBytes(zstSize)}`);

    console.log("Decompressing tar...");
    await run([BIN, "decompress", "-i", zstPath, "-o", restoredTarPath, "--progress", ...extraZstdArgs]);

    const restoredSize = statSync(restoredTarPath).size;
    console.log(`Restored tar size: ${formatBytes(restoredSize)}`);

    const original = await Bun.file(tarPath).arrayBuffer();
    const restored = await Bun.file(restoredTarPath).arrayBuffer();

    if (original.byteLength !== restored.byteLength) {
      throw new Error("Restored tar size mismatch");
    }

    const a = new Uint8Array(original);
    const b = new Uint8Array(restored);

    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        throw new Error(`Restored tar mismatch at byte ${i}`);
      }
    }

    console.log("✓ Roundtrip verified");
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
