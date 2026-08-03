import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const workflow = readFileSync(
  new URL("../.github/workflows/release.yml", import.meta.url),
  "utf8",
).replaceAll("\r\n", "\n");

test("release targets are independent from runner OS versions", () => {
  for (const target of [
    "aarch64-macos.14.0",
    "x86_64-macos.14.0",
    "x86_64-linux-gnu.2.35",
    "aarch64-linux-gnu.2.35",
    "x86_64-windows-msvc",
  ]) {
    assert.match(workflow, new RegExp(`zig-target: ${target.replaceAll(".", "\\.")}`));
  }
  assert.match(workflow, /-Dtarget=\$\{\{ matrix\.zig-target \}\}/);
});

test("macOS artifacts are checked for the 14.0 deployment target", () => {
  assert.match(workflow, /Verify macOS deployment target/);
  assert.match(workflow, /otool -l zig-out\/bin\/zig-zstd/);
  assert.match(workflow, /\[ "\$minos" != "14\.0" \]/);
});
