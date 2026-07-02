import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  DEFAULT_MODEL,
  assembleAgentEnv,
  buildInvocation,
  findGatewayKey,
  runAgent,
} from "./agent.ts";
import { buildCli, prewarmWorkspace, scaffoldWorkspace } from "./scaffold.ts";
import { DEFAULT_JUDGE_MODEL } from "./judge.ts";
import { ensureSandboxAuth, packRepo, runCaseInSandbox } from "./sandbox.ts";
import { runChecks } from "./grade.ts";
import { formatDuration } from "./util.ts";
import type { AgentRunResult, CaseResult, EvalCase, RunnerOptions } from "./types.ts";

const USAGE = `usage: pnpm eval [options] [case ...]

Runs Claude Code headless (claude -p) through the Vercel AI Gateway against a
freshly scaffolded zero-native workspace, then grades the result.

options:
  --list               list available cases and exit
  --dry-run            everything except the model call: scaffold, deliver the
                       skill, print the env assembly + claude argv, then run
                       the graders against the workspace as-scaffolded
  --skip-live          skip snapshot_grep checks (no app launch)
  --skip-permissions   run claude with --dangerously-skip-permissions instead
                       of acceptEdits + an allowlist (sandbox dirs only)
  --keep-workspaces    do not delete .workspaces/<case> after grading
  --concurrency <n>    run up to n cases in parallel (default: 2 locally,
                       all cases with --sandbox)
  --sandbox            run each case in its own Vercel Sandbox microVM
                       (needs VERCEL_OIDC_TOKEN via vercel link + env pull)
  --sandbox-vcpus <n>  vCPUs per sandbox (default 4; 2048 MB RAM per vCPU)
  --model <slug>       coder model slug (default: ${DEFAULT_MODEL};
                       also via ZN_EVAL_MODEL)
  --judge-model <slug> judge model slug for llm_judge checks (default:
                       ${DEFAULT_JUDGE_MODEL}; also via ZN_EVAL_JUDGE_MODEL)

env:
  AI_GATEWAY_API_KEY   Vercel AI Gateway API key (or VERCEL_AI_GATEWAY_API_KEY)
`;

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const cases = loadCases(options);
  if (cases.length === 0) {
    console.error("no cases selected");
    process.exit(2);
  }

  if (options.sandbox && options.dryRun) {
    console.error("--sandbox and --dry-run are mutually exclusive (dry runs are local by definition)");
    process.exit(2);
  }
  const gatewayKey = findGatewayKey(process.env);
  if (!gatewayKey && !options.dryRun) {
    console.error(
      "AI_GATEWAY_API_KEY (or VERCEL_AI_GATEWAY_API_KEY) is not set.\n" +
        "Real runs need a Vercel AI Gateway key; use --dry-run to exercise everything except the model call.",
    );
    process.exit(2);
  }

  const runStamp = new Date().toISOString().replace(/[:.]/g, "-");
  const runResultsDir = join(options.evalsRoot, "results", runStamp);
  const workspacesDir = join(options.evalsRoot, ".workspaces");
  mkdirSync(runResultsDir, { recursive: true });

  let cliPath: string | undefined;
  let tarballPath: string | undefined;
  if (options.sandbox) {
    ensureSandboxAuth(options.evalsRoot);
    console.log("[sandbox] packing repo working tree for upload...");
    tarballPath = await packRepo(options.repoRoot);
  } else {
    cliPath = await buildCli(options.repoRoot);
  }

  const concurrency = Math.max(
    1,
    Math.min(options.concurrency ?? (options.sandbox ? cases.length : 2), cases.length),
  );
  if (cases.length > 1) {
    console.log(`running ${cases.length} cases, ${concurrency} at a time${options.sandbox ? " (vercel sandbox)" : ""}`);
  }
  const results = await runPool(cases, concurrency, async (evalCase) => {
    const log = (line: string): void => console.log(`[${evalCase.name}] ${line}`);
    const caseResultsDir = join(runResultsDir, evalCase.name);
    mkdirSync(caseResultsDir, { recursive: true });
    try {
      if (options.sandbox) {
        return await runCaseInSandbox({
          evalCase,
          tarballPath: tarballPath!,
          gatewayKey: gatewayKey!,
          model: options.model,
          judgeModel: options.judgeModel,
          vcpus: options.sandboxVcpus,
          localResultsDir: caseResultsDir,
          log,
        });
      }
      return await runCaseLocal(evalCase, options, {
        cliPath: cliPath!,
        workspacesDir,
        caseResultsDir,
        gatewayKey,
        log,
      });
    } catch (error) {
      // One crashed case (sandbox provisioning, scaffold failure, ...) should
      // not kill the rest of the suite.
      log(`FAILED: ${(error as Error).message}`);
      return {
        case: evalCase.name,
        workspace: "-",
        startedAt: new Date().toISOString(),
        dryRun: options.dryRun,
        agent: {
          status: "error" as const,
          model: options.model,
          durationMs: 0,
          errorDetail: (error as Error).message,
        },
        checks: [],
        passed: false,
      };
    }
  });

  if (tarballPath) rmSync(tarballPath, { force: true });
  writeFileSync(join(runResultsDir, "summary.json"), `${JSON.stringify(results, null, 2)}\n`);
  printSummary(results, options);
  console.log(`\nresults: ${runResultsDir}`);
  const failed = results.filter((result) => !result.passed);
  // In --dry-run, grader failures against the untouched scaffold are expected
  // (they prove the graders detect a missing solution) — exit 0.
  process.exit(failed.length > 0 && !options.dryRun ? 1 : 0);
}

interface LocalCaseContext {
  cliPath: string;
  workspacesDir: string;
  caseResultsDir: string;
  gatewayKey: string | undefined;
  log: (line: string) => void;
}

async function runCaseLocal(
  evalCase: EvalCase,
  options: RunnerOptions,
  context: LocalCaseContext,
): Promise<CaseResult> {
  const { log } = context;
  const startedAt = new Date().toISOString();

  const workspace = await scaffoldWorkspace(
    options.repoRoot,
    context.cliPath,
    context.workspacesDir,
    evalCase.name,
    evalCase.frontend,
  );
  log(`[scaffold] workspace ready: ${workspace.path}`);
  log(`[scaffold] skill delivered: .claude/skills/native-ui/SKILL.md`);
  if (!options.dryRun) await prewarmWorkspace(workspace, log);

  const configDir = join(context.caseResultsDir, "claude-config");
  mkdirSync(configDir, { recursive: true });
  const invocation = buildInvocation({
    prompt: evalCase.prompt,
    model: options.model,
    maxTurns: evalCase.maxTurns,
    workspace: workspace.path,
    skipPermissions: options.skipPermissions,
  });

  let agent: AgentRunResult;
  if (options.dryRun) {
    const agentEnv = assembleAgentEnv(context.gatewayKey ?? "<AI_GATEWAY_API_KEY>", options.repoRoot, configDir);
    log("[dry-run] env overrides for the claude subprocess:");
    for (const [key, value] of Object.entries(agentEnv.redacted)) {
      log(`  ${key}=${value}`);
    }
    log(`[dry-run] claude ${formatArgv(invocation.argv)}`);
    log(`[dry-run] cwd: ${invocation.cwd}`);
    agent = { status: "dry_run", model: options.model, durationMs: 0 };
  } else {
    const agentEnv = assembleAgentEnv(context.gatewayKey!, options.repoRoot, configDir);
    log(`[agent] claude -p (model ${options.model}, max ${evalCase.maxTurns} turns, timeout ${formatDuration(evalCase.timeoutMs)})...`);
    agent = await runAgent({
      invocation,
      agentEnv,
      model: options.model,
      timeoutMs: evalCase.timeoutMs,
      resultsDir: context.caseResultsDir,
    });
    const cost = agent.totalCostUsd !== undefined ? ` $${agent.totalCostUsd.toFixed(4)}` : "";
    const turns = agent.numTurns !== undefined ? ` ${agent.numTurns} turns` : "";
    log(`[agent] ${agent.status} in ${formatDuration(agent.durationMs)}${turns}${cost}`);
    if (agent.errorDetail) log(`[agent] ${agent.errorDetail}`);
  }

  const checks = await runChecks(evalCase.checks, {
    workspace,
    log,
    skipLive: options.skipLive,
    dryRun: options.dryRun,
    taskPrompt: evalCase.prompt,
    judgeModel: options.judgeModel,
    gatewayKey: context.gatewayKey,
  });
  const agentOk = agent.status === "completed" || agent.status === "dry_run";
  // Advisory judge checks record a score but never fail the case.
  const passed =
    agentOk && checks.every((check) => check.status !== "fail" || check.advisory === true);
  const caseResult: CaseResult = {
    case: evalCase.name,
    workspace: workspace.path,
    startedAt,
    dryRun: options.dryRun,
    agent,
    checks,
    passed,
  };
  writeFileSync(join(context.caseResultsDir, "result.json"), `${JSON.stringify(caseResult, null, 2)}\n`);
  if (!options.keepWorkspaces) rmSync(workspace.path, { recursive: true, force: true });
  return caseResult;
}

/** Run `worker` over `items` with at most `limit` in flight; results keep item order. */
async function runPool<T, R>(
  items: T[],
  limit: number,
  worker: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const lanes = Array.from({ length: limit }, async () => {
    while (next < items.length) {
      const index = next;
      next += 1;
      results[index] = await worker(items[index]!);
    }
  });
  await Promise.all(lanes);
  return results;
}

function parseArgs(argv: string[]): RunnerOptions {
  const evalsRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const repoRoot = resolve(evalsRoot, "..");
  const options: RunnerOptions = {
    repoRoot,
    evalsRoot,
    caseNames: [],
    model: process.env.ZN_EVAL_MODEL ?? DEFAULT_MODEL,
    judgeModel: process.env.ZN_EVAL_JUDGE_MODEL ?? DEFAULT_JUDGE_MODEL,
    dryRun: false,
    skipLive: false,
    skipPermissions: false,
    keepWorkspaces: false,
    concurrency: undefined,
    sandbox: false,
    sandboxVcpus: 4,
  };
  let listOnly = false;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]!;
    switch (arg) {
      case "--help":
      case "-h":
        console.log(USAGE);
        process.exit(0);
        break;
      case "--list":
        listOnly = true;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--skip-live":
        options.skipLive = true;
        break;
      case "--skip-permissions":
        options.skipPermissions = true;
        break;
      case "--keep-workspaces":
        options.keepWorkspaces = true;
        break;
      case "--model": {
        const value = argv[index + 1];
        if (!value) {
          console.error("--model requires a value");
          process.exit(2);
        }
        options.model = value;
        index += 1;
        break;
      }
      case "--judge-model": {
        const value = argv[index + 1];
        if (!value) {
          console.error("--judge-model requires a value");
          process.exit(2);
        }
        options.judgeModel = value;
        index += 1;
        break;
      }
      case "--sandbox":
        options.sandbox = true;
        break;
      case "--concurrency":
      case "--sandbox-vcpus": {
        const value = Number(argv[index + 1]);
        if (!Number.isInteger(value) || value <= 0) {
          console.error(`${arg} requires a positive integer`);
          process.exit(2);
        }
        if (arg === "--concurrency") options.concurrency = value;
        else options.sandboxVcpus = value;
        index += 1;
        break;
      }
      default:
        if (arg.startsWith("-")) {
          console.error(`unknown option: ${arg}\n\n${USAGE}`);
          process.exit(2);
        }
        options.caseNames.push(arg);
    }
  }
  if (listOnly) {
    for (const name of discoverCaseNames(options.evalsRoot)) console.log(name);
    process.exit(0);
  }
  return options;
}

function discoverCaseNames(evalsRoot: string): string[] {
  const casesDir = join(evalsRoot, "cases");
  return readdirSync(casesDir)
    .filter((entry) => existsSync(join(casesDir, entry, "eval.json")))
    .sort();
}

function loadCases(options: RunnerOptions): EvalCase[] {
  const names = options.caseNames.length > 0 ? options.caseNames : discoverCaseNames(options.evalsRoot);
  return names.map((name) => {
    const path = join(options.evalsRoot, "cases", name, "eval.json");
    if (!existsSync(path)) {
      console.error(`unknown case: ${name} (no ${path})`);
      process.exit(2);
    }
    const parsed = JSON.parse(readFileSync(path, "utf8")) as EvalCase;
    validateCase(parsed, name, path);
    return parsed;
  });
}

function validateCase(evalCase: EvalCase, name: string, path: string): void {
  const problems: string[] = [];
  if (evalCase.name !== name) problems.push(`name "${evalCase.name}" != directory "${name}"`);
  if (typeof evalCase.prompt !== "string" || evalCase.prompt.length < 20) problems.push("prompt missing/too short");
  if (evalCase.frontend !== "native") problems.push(`unsupported frontend "${evalCase.frontend}"`);
  if (!Number.isFinite(evalCase.timeoutMs) || evalCase.timeoutMs <= 0) problems.push("timeoutMs must be positive");
  if (!Number.isInteger(evalCase.maxTurns) || evalCase.maxTurns <= 0) problems.push("maxTurns must be a positive integer");
  if (!Array.isArray(evalCase.checks) || evalCase.checks.length === 0) problems.push("checks must be non-empty");
  if (problems.length > 0) {
    console.error(`invalid case config ${path}:\n  ${problems.join("\n  ")}`);
    process.exit(2);
  }
}

function printSummary(results: CaseResult[], options: RunnerOptions): void {
  console.log(
    `\n=== summary (coder: ${options.model}, judge: ${options.judgeModel}${options.dryRun ? ", DRY RUN" : ""}) ===`,
  );
  const rows = results.map((result) => {
    const checkSummary = result.checks
      .map((check) => (check.status === "pass" ? "P" : check.status === "skipped" ? "s" : "F"))
      .join("");
    const judgeScores = result.checks
      .filter((check) => check.type === "llm_judge" && check.score !== undefined)
      .map((check) => `${check.score!.toFixed(1)}/10`);
    return {
      case: result.case,
      result: result.passed ? "PASS" : "FAIL",
      checks: checkSummary,
      judge: judgeScores.join(" ") || "-",
      turns: result.agent.numTurns?.toString() ?? "-",
      cost: result.agent.totalCostUsd !== undefined ? `$${result.agent.totalCostUsd.toFixed(4)}` : "-",
      time: formatDuration(result.agent.durationMs + result.checks.reduce((sum, check) => sum + check.durationMs, 0)),
    };
  });
  const columns = ["case", "result", "checks", "judge", "turns", "cost", "time"] as const;
  const widths = columns.map((column) =>
    Math.max(column.length, ...rows.map((row) => row[column].length)),
  );
  const line = (cells: string[]): string =>
    cells.map((cell, index) => cell.padEnd(widths[index]!)).join("  ");
  console.log(line([...columns]));
  console.log(line(widths.map((width) => "-".repeat(width))));
  for (const row of rows) console.log(line(columns.map((column) => row[column])));
}

function formatArgv(argv: string[]): string {
  return argv
    .map((arg) => (/[\s"']/.test(arg) ? JSON.stringify(arg.length > 120 ? `${arg.slice(0, 120)}...` : arg) : arg))
    .join(" ");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack ?? error.message : error);
  process.exit(1);
});
