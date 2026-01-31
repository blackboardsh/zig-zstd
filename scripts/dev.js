#!/usr/bin/env node
import { spawnSync } from "child_process";

function run(cmd, args = []) {
  const result = spawnSync(cmd, args, { stdio: "inherit" });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

const rawArgs = process.argv.slice(2);
let sizeArg;
let extraArgs = [];

if (rawArgs.length > 0) {
  const maybeSize = Number(rawArgs[0]);
  if (Number.isFinite(maybeSize)) {
    sizeArg = rawArgs[0];
    extraArgs = rawArgs.slice(1);
  } else {
    extraArgs = rawArgs;
  }
}

run("bun", ["run", "setup"]);
run("bun", ["run", "build"]);
run("bun", ["run", "zig-test"]);

const testArgs = ["test-progress.ts"];
if (sizeArg) testArgs.push(sizeArg);
if (extraArgs.length > 0) testArgs.push(...extraArgs);
run("bun", testArgs);
