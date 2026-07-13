// The layout-neutral runner (build/ts_run.mjs) under both node capability
// tiers. On node >= 22.15 module.registerHooks exists and the runner strips
// node_modules-resident .ts targets with the transpiler's own toolchain. On
// older node the hook cannot be registered: repo-checkout targets must keep
// running natively, and a node_modules-resident target must fail fast with
// the one-line 22.15+ teaching instead of node's raw
// ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING.
//
// The under-22.15 tier is simulated by deleting module.registerHooks in a
// --import preload before the runner loads — the spawned node then presents
// exactly the capability surface the runner's check reads, with no
// test-only seam inside ts_run.mjs itself.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const pkg = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const runner = path.join(path.dirname(path.dirname(pkg)), "build", "ts_run.mjs");

// Pins the teaching verbatim: the string the runner prints on an old node.
const teaching = "TypeScript apps need Node.js 22.15+ for the npm-installed SDK";

// A module whose types only node's stripping (native or hooked) can remove.
const typedModule = 'const answer: number = 42;\nconsole.log("RAN", answer);\n';

function withFixture<T>(root: string, targetRel: string, run: (target: string) => T): T {
  const dir = fs.mkdtempSync(root);
  try {
    const target = path.join(dir, targetRel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, typedModule);
    return run(target);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function runRunner(target: string, { withoutHooks = false } = {}) {
  const args: string[] = [];
  if (withoutHooks) {
    const stub = path.join(path.dirname(target), "no_hooks.mjs");
    fs.writeFileSync(stub, 'import module from "node:module";\ndelete module.registerHooks;\n');
    args.push("--import", pathToFileURL(stub).href);
  }
  args.push(runner, target);
  return spawnSync(process.execPath, args, { encoding: "utf8" });
}

test("without registerHooks, a node_modules-resident target is taught 22.15+ before import", () => {
  withFixture(path.join(os.tmpdir(), "tsrun-npm-"), path.join("node_modules", "app", "core.ts"), (target) => {
    const result = runRunner(target, { withoutHooks: true });
    assert.notEqual(result.status, 0);
    assert.ok(result.stderr.includes(teaching), `expected the teaching, got:\n${result.stderr}`);
    assert.ok(result.stderr.includes(process.version));
    assert.ok(!result.stdout.includes("RAN"), "the target must not be imported");
  });
});

test("without registerHooks, a repo-checkout target still runs natively", () => {
  withFixture(path.join(os.tmpdir(), "tsrun-checkout-"), path.join("app", "core.ts"), (target) => {
    const result = runRunner(target, { withoutHooks: true });
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.stdout.includes("RAN 42"));
    assert.ok(!result.stderr.includes(teaching));
  });
});

test("with registerHooks, a node_modules-resident target is stripped and runs", () => {
  // The fixture lives under packages/core so the hook's ancestor
  // node_modules walk from the target resolves this package's own
  // @typescript/typescript6 dev install — the npm layout in miniature.
  withFixture(path.join(pkg, ".tsrun-fixture-"), path.join("node_modules", "app", "core.ts"), (target) => {
    const result = runRunner(target);
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.stdout.includes("RAN 42"));
    assert.ok(!result.stderr.includes(teaching));
  });
});
