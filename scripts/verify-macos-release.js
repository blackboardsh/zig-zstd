import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const version = process.argv[2] || process.env.RELEASE_VERSION || packageJson.version;
const arch = process.env.EXPECTED_ARCH || process.arch;
const machoArch = { x64: 'x86_64', arm64: 'arm64' }[arch];
assert.match(version, /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/, 'Expected an explicit release version');
assert.equal(process.platform, 'darwin', 'Run release validation on macOS');
assert.ok(machoArch, `Unsupported macOS architecture: ${arch}`);
assert.equal(process.arch, arch, 'Run release validation in a native target process');
assert.equal(execFileSync('uname', ['-m'], { encoding: 'utf8' }).trim(), machoArch, 'Runner architecture');

const product = packageJson.name;
const target = `darwin-${arch}`;
const releaseUrl = `https://electrobun-artifacts.blackboard.sh/${product}/releases/${version}`;
const temporary = mkdtempSync(join(tmpdir(), `${product}-published-`));

function download(url, destination) {
  console.log(`Downloading ${url}`);
  execFileSync('curl', ['--fail', '--show-error', '--silent', '--location', '--retry', '3', '--output', destination, url], { stdio: 'inherit' });
}

try {
  const manifestPath = join(temporary, 'manifest.json');
  download(`${releaseUrl}/manifest.json`, manifestPath);
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.schemaVersion, 1, 'Release manifest schema');
  assert.equal(manifest.product, product, 'Release manifest product');
  assert.equal(manifest.version, version, 'Release manifest version');
  const artifact = manifest.artifacts?.[target];
  assert.ok(artifact, `Missing ${target} release artifact`);
  assert.equal(artifact.url, `${releaseUrl}/${product}-${target}.tar.gz`, 'Immutable artifact URL');
  assert.match(artifact.sha256, /^[0-9a-f]{64}$/, 'Release SHA-256');
  assert.ok(Number.isSafeInteger(artifact.size) && artifact.size > 0, 'Release size');

  const archivePath = join(temporary, 'release.tar.gz');
  download(artifact.url, archivePath);
  const archive = readFileSync(archivePath);
  assert.equal(archive.length, artifact.size, 'Downloaded artifact size');
  assert.equal(createHash('sha256').update(archive).digest('hex'), artifact.sha256, 'Downloaded artifact SHA-256');
  const directory = join(temporary, 'release');
  mkdirSync(directory);
  execFileSync('tar', ['-xzf', archivePath, '-C', directory], { stdio: 'inherit' });

  const binary = join(directory, 'zig-zstd');
  console.log(execFileSync('file', [binary], { encoding: 'utf8' }).trim());
  assert.equal(execFileSync('lipo', ['-archs', binary], { encoding: 'utf8' }).trim(), machoArch, 'Release binary architecture');
  const loadCommands = execFileSync('otool', ['-l', binary], { encoding: 'utf8' });
  const minimumOS = loadCommands.match(/^\s*minos\s+(\S+)$/m)?.[1];
  assert.match(minimumOS || '', /^14\.0(?:\.0)?$/, 'Release binary must retain the macOS 14.0 deployment target');
  const dependencies = execFileSync('otool', ['-L', binary], { encoding: 'utf8' })
    .trim().split('\n').slice(1).map((line) => line.trim().split(' (')[0]);
  assert.ok(dependencies.length > 0, 'Expected macOS system dependencies');
  for (const dependency of dependencies) {
    assert.ok(dependency.startsWith('/usr/lib/') || dependency.startsWith('/System/Library/'), `Non-system dependency: ${dependency}`);
  }
  console.log(`Verified ${target}, macOS ${minimumOS}, system dependencies: ${dependencies.join(', ')}`);
  execFileSync(process.execPath, [fileURLToPath(new URL('test-release-binaries.js', import.meta.url)), directory, arch], { stdio: 'inherit' });
  console.log(`Validated published ${product} ${version} ${target} (${artifact.sha256})`);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
