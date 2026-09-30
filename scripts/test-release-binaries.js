import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const directory = resolve(process.argv[2] ?? 'dist');
const arch = process.argv[3] ?? process.arch;
const binary = join(directory, `zig-zstd${process.platform === 'win32' ? '.exe' : ''}`);
if (process.platform === 'win32') {
  const bytes = readFileSync(binary);
  const pe = bytes.readUInt32LE(0x3c);
  assert.equal(bytes.readUInt32LE(pe), 0x4550, 'PE signature');
  assert.equal(bytes.readUInt16LE(pe + 4), { arm64: 0xaa64, x64: 0x8664 }[arch], 'PE architecture');
  assert.equal(process.arch, arch, 'Run release validation in a native target process');
}
const temporary = mkdtempSync(join(tmpdir(), 'zig-zstd-release-'));
try {
  const input = join(temporary, 'input.bin');
  const compressed = join(temporary, 'compressed.zst');
  const restored = join(temporary, 'restored.bin');
  const content = Buffer.from('Windows ARM64 compression roundtrip\n'.repeat(4096));
  writeFileSync(input, content);
  execFileSync(binary, ['compress', '-i', input, '-o', compressed, '-l', '3'], { stdio: 'inherit' });
  execFileSync(binary, ['decompress', '-i', compressed, '-o', restored], { stdio: 'inherit' });
  assert.deepEqual(readFileSync(restored), content);
  console.log(`Validated ${arch} release binary and compression roundtrip`);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
