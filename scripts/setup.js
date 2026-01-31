#!/usr/bin/env node
/**
 * Setup script for zig-zstd development
 * - Initializes git submodules (zstd)
 * - Vendors Zig compiler if not already present
 * Based on zig-bsdiff's vendoring approach
 */

import { execSync } from 'child_process';
import { existsSync, mkdirSync, rmSync, unlinkSync } from 'fs';
import { join } from 'path';

const ZIG_VERSION = '0.13.0';

async function initSubmodules() {
  console.log('Initializing git submodules...');
  try {
    execSync('git submodule update --init --recursive', { stdio: 'inherit' });
    console.log('✓ Submodules initialized');
  } catch (error) {
    console.error('Failed to initialize submodules:', error.message);
    process.exit(1);
  }
}

async function vendorZig() {
  const platform = process.platform;
  const zigBinary = platform === 'win32' ? 'zig.exe' : 'zig';
  const zigBinPath = join(process.cwd(), 'vendors', 'zig', zigBinary);

  if (existsSync(zigBinPath)) {
    console.log('✓ Zig already vendored');
    return;
  }

  console.log('Vendoring Zig compiler...');

  const arch = process.arch === 'arm64' ? 'aarch64' : 'x86_64';

  try {
    const vendorsDir = join(process.cwd(), 'vendors', 'zig');
    mkdirSync(vendorsDir, { recursive: true });

    if (platform === 'darwin') {
      const url = `https://ziglang.org/download/${ZIG_VERSION}/zig-macos-${arch}-${ZIG_VERSION}.tar.xz`;
      execSync(
        `curl -L ${url} | tar -xJ --strip-components=1 -C vendors/zig zig-macos-${arch}-${ZIG_VERSION}/zig zig-macos-${arch}-${ZIG_VERSION}/lib zig-macos-${arch}-${ZIG_VERSION}/doc`,
        { stdio: 'inherit' }
      );
      console.log('✓ Zig vendored for macOS');
    } else if (platform === 'linux') {
      const url = `https://ziglang.org/download/${ZIG_VERSION}/zig-linux-${arch}-${ZIG_VERSION}.tar.xz`;
      execSync(
        `curl -L ${url} | tar -xJ --strip-components=1 -C vendors/zig zig-linux-${arch}-${ZIG_VERSION}/zig zig-linux-${arch}-${ZIG_VERSION}/lib zig-linux-${arch}-${ZIG_VERSION}/doc`,
        { stdio: 'inherit' }
      );
      console.log('✓ Zig vendored for Linux');
    } else if (platform === 'win32') {
      const zigFolder = `zig-windows-${arch}-${ZIG_VERSION}`;
      const zipPath = join(process.cwd(), 'vendors', 'zig.zip');
      const tempDir = join(process.cwd(), 'vendors', 'zig-temp');

      execSync(
        `curl -L https://ziglang.org/download/${ZIG_VERSION}/${zigFolder}.zip -o "${zipPath}"`,
        { stdio: 'inherit' }
      );

      execSync(
        `powershell -ExecutionPolicy Bypass -Command "Expand-Archive -Path '${zipPath}' -DestinationPath '${tempDir}' -Force"`,
        { stdio: 'inherit' }
      );

      execSync(
        `powershell -ExecutionPolicy Bypass -Command "Move-Item -Path '${tempDir}\\${zigFolder}\\zig.exe' -Destination '${vendorsDir}' -Force; Move-Item -Path '${tempDir}\\${zigFolder}\\lib' -Destination '${vendorsDir}' -Force"`,
        { stdio: 'inherit' }
      );

      if (existsSync(zipPath)) {
        unlinkSync(zipPath);
      }
      if (existsSync(tempDir)) {
        rmSync(tempDir, { recursive: true, force: true });
      }

      console.log('✓ Zig vendored for Windows');
    } else {
      console.error(`Unsupported platform: ${platform}`);
      process.exit(1);
    }
  } catch (error) {
    console.error('Failed to vendor Zig:', error.message);
    process.exit(1);
  }
}

async function setup() {
  await initSubmodules();
  await vendorZig();
  console.log('\n✅ Setup complete! You can now run: npm run build');
}

setup().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
