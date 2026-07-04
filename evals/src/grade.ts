import { spawn } from "node:child_process";
import { existsSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { exec, resolveFiles, tailLines } from "./util.ts";
import { judgeWorkspace } from "./judge.ts";
import type { CheckResult, CheckSpec, LlmJudgeCheck, SnapshotGrepCheck } from "./types.ts";
import type { Workspace } from "./scaffold.ts";

export interface GradeContext {
  workspace: Workspace;
  /** Per-case logger (prefixes the case name when cases run in parallel). */
  log: (line: string) => void;
  /** Skip live snapshot checks (report "skipped"). */
  skipLive: boolean;
  /** Dry runs make no model calls; llm_judge checks report "skipped". */
  dryRun: boolean;
  /** The case's task prompt, shown to the judge alongside the code. */
  taskPrompt: string;
  judgeModel: string;
  gatewayKey?: string | undefined;
}

export async function runChecks(
  checks: CheckSpec[],
  context: GradeContext,
): Promise<CheckResult[]> {
  const results: CheckResult[] = [];
  for (const check of checks) {
    const started = Date.now();
    const result = await runCheck(check, context);
    results.push({ ...result, durationMs: Date.now() - started });
    const marker = result.status === "pass" ? "PASS" : result.status === "skipped" ? "SKIP" : "FAIL";
    context.log(`[check] ${marker} ${result.description}`);
    if (result.detail && (result.status === "fail" || result.type === "llm_judge")) {
      context.log(indent(result.detail, "        | "));
    }
  }
  return results;
}

type PendingResult = Omit<CheckResult, "durationMs">;

async function runCheck(check: CheckSpec, context: GradeContext): Promise<PendingResult> {
  switch (check.type) {
    case "build_test":
      return buildTest(check.args ?? [], context);
    case "markup_check":
      return markupCheck(context);
    case "file_grep":
      return fileGrep(check.files, check.pattern, check.expect, check.description, context);
    case "snapshot_grep":
      return snapshotGrep(check, context);
    case "llm_judge":
      return llmJudge(check, context);
  }
}

async function llmJudge(check: LlmJudgeCheck, context: GradeContext): Promise<PendingResult> {
  const advisory = check.advisory ?? true;
  const minScore = check.minScore ?? 6;
  const description = `judge${advisory ? " (advisory)" : ""}: ${check.description}`;
  if (context.dryRun) {
    return { type: "llm_judge", description, status: "skipped", advisory, detail: "--dry-run (no model calls)" };
  }
  if (!context.gatewayKey) {
    return { type: "llm_judge", description, status: "skipped", advisory, detail: "no gateway key" };
  }
  let verdict;
  try {
    verdict = await judgeWorkspace({
      gatewayKey: context.gatewayKey,
      model: context.judgeModel,
      taskPrompt: context.taskPrompt,
      criteria: check.criteria,
      workspacePath: context.workspace.path,
      fileSelectors: check.files,
    });
  } catch (error) {
    const detail = `judge call failed: ${(error as Error).message}`;
    return advisory
      ? { type: "llm_judge", description, status: "skipped", advisory, detail }
      : { type: "llm_judge", description, status: "fail", advisory, detail };
  }
  const lines = verdict.scores.map(
    (entry) => `${entry.score.toFixed(1).padStart(4)}  ${entry.criterion}${entry.note ? ` — ${entry.note}` : ""}`,
  );
  const detail = `overall ${verdict.overall.toFixed(1)}/10 (min ${minScore})\n${lines.join("\n")}${verdict.summary ? `\n${verdict.summary}` : ""}`;
  return {
    type: "llm_judge",
    description,
    status: verdict.overall >= minScore ? "pass" : "fail",
    score: verdict.overall,
    advisory,
    detail,
  };
}

async function buildTest(args: string[], context: GradeContext): Promise<PendingResult> {
  const description = `zig build test${args.length ? ` ${args.join(" ")}` : ""}`;
  const result = await exec("zig", ["build", "test", ...args], {
    cwd: context.workspace.path,
    timeoutMs: 15 * 60 * 1000,
  });
  if (result.code === 0) return { type: "build_test", description, status: "pass" };
  return {
    type: "build_test",
    description,
    status: "fail",
    detail: result.timedOut ? "timed out" : tailLines(result),
  };
}

async function markupCheck(context: GradeContext): Promise<PendingResult> {
  const files = resolveFiles(context.workspace.path, "src/*.zml");
  if (files.length === 0) {
    return {
      type: "markup_check",
      description: "native markup check src/*.zml",
      status: "fail",
      detail: "no .zml files found under src/",
    };
  }
  const failures: string[] = [];
  for (const file of files) {
    const result = await exec(context.workspace.cliPath, ["markup", "check", file], {
      cwd: context.workspace.path,
      timeoutMs: 60 * 1000,
    });
    if (result.code !== 0) {
      failures.push(`${relative(context.workspace.path, file)}:\n${tailLines(result, 8)}`);
    }
  }
  const description = `native markup check (${files.map((f) => relative(context.workspace.path, f)).join(", ")})`;
  if (failures.length === 0) return { type: "markup_check", description, status: "pass" };
  return { type: "markup_check", description, status: "fail", detail: failures.join("\n") };
}

function fileGrep(
  files: string,
  pattern: string,
  expect: boolean,
  description: string,
  context: GradeContext,
): PendingResult {
  const paths = resolveFiles(context.workspace.path, files);
  const regex = new RegExp(pattern, "m");
  const matching = paths.filter((path) => regex.test(readFileSync(path, "utf8")));
  const found = matching.length > 0;
  if (found === expect) return { type: "file_grep", description, status: "pass" };
  const detail = expect
    ? paths.length === 0
      ? `no files matched selector "${files}"`
      : `pattern /${pattern}/ not found in: ${paths.map((p) => relative(context.workspace.path, p)).join(", ")}`
    : `pattern /${pattern}/ unexpectedly found in: ${matching.map((p) => relative(context.workspace.path, p)).join(", ")}`;
  return { type: "file_grep", description, status: "fail", detail };
}

/**
 * Live grading through the automation harness: build with -Dautomation=true,
 * launch the app, `native automate wait`, then grep the widget snapshot.
 * Mirrors the repo's linux-canvas-smoke CI job, but local-macOS.
 */
async function snapshotGrep(
  check: SnapshotGrepCheck,
  context: GradeContext,
): Promise<PendingResult> {
  const description = `snapshot: ${check.description}`;
  if (context.skipLive) {
    return { type: "snapshot_grep", description, status: "skipped", detail: "--skip-live" };
  }
  if (process.platform !== "darwin") {
    return { type: "snapshot_grep", description, status: "skipped", detail: "requires macOS" };
  }
  const workspace = context.workspace.path;
  const build = await exec(
    "zig",
    ["build", "-Dplatform=macos", "-Dweb-engine=system", "-Dautomation=true"],
    { cwd: workspace, timeoutMs: 15 * 60 * 1000 },
  );
  if (build.code !== 0) {
    return { type: "snapshot_grep", description, status: "fail", detail: `automation build failed:\n${tailLines(build)}` };
  }
  const binary = findAppBinary(workspace);
  if (!binary) {
    return { type: "snapshot_grep", description, status: "fail", detail: "no executable in zig-out/bin" };
  }
  rmSync(join(workspace, ".zig-cache", "native-sdk-automation"), { recursive: true, force: true });
  const app = spawn(binary, [], { cwd: workspace, stdio: "ignore" });
  try {
    const wait = await exec(context.workspace.cliPath, ["automate", "wait"], {
      cwd: workspace,
      timeoutMs: 60 * 1000,
    });
    // `automate wait` reports status on stderr and exits 0 once ready.
    if (wait.code !== 0 || !`${wait.stdout}\n${wait.stderr}`.includes("ready=true")) {
      return {
        type: "snapshot_grep",
        description,
        status: "fail",
        detail: `automate wait did not report ready=true:\n${tailLines(wait, 6)}`,
      };
    }
    const snapshotPath = join(workspace, ".zig-cache", "native-sdk-automation", "snapshot.txt");
    const regexes = check.patterns.map((pattern) => new RegExp(pattern, "m"));
    // Widget lines appear in the snapshot only after the first rendered
    // frame (widget_nodes starts at 0), so poll rather than read once.
    const deadline = Date.now() + 30 * 1000;
    let missing: string[] = check.patterns;
    while (Date.now() < deadline) {
      const snapshot = existsSync(snapshotPath) ? readFileSync(snapshotPath, "utf8") : "";
      missing = check.patterns.filter((_, index) => !regexes[index]!.test(snapshot));
      if (missing.length === 0) break;
      await sleep(300);
    }
    if (missing.length === 0) return { type: "snapshot_grep", description, status: "pass" };
    return {
      type: "snapshot_grep",
      description,
      status: "fail",
      detail: `snapshot missing patterns:\n${missing.map((pattern) => `  /${pattern}/`).join("\n")}`,
    };
  } finally {
    app.kill("SIGKILL");
  }
}

function findAppBinary(workspace: string): string | undefined {
  const binDir = join(workspace, "zig-out", "bin");
  let entries: string[];
  try {
    entries = readdirSync(binDir);
  } catch {
    return undefined;
  }
  for (const entry of entries) {
    const path = join(binDir, entry);
    const stats = statSync(path);
    if (stats.isFile() && (stats.mode & 0o111) !== 0) return path;
  }
  return undefined;
}

function indent(text: string, prefix: string): string {
  return text
    .split("\n")
    .map((line) => `${prefix}${line}`)
    .join("\n");
}
