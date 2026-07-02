import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { Sandbox } from "@vercel/sandbox";
import { exec } from "./util.ts";
import type { CaseResult, EvalCase } from "./types.ts";

const SANDBOX_TIMEOUT_MS = 45 * 60 * 1000;
/** Repo location inside the sandbox (relative to /vercel/sandbox). */
const REPO_DIR = "repo";

/**
 * Auth for Sandbox.create: the SDK reads VERCEL_OIDC_TOKEN. Locally that
 * comes from `vercel link` + `vercel env pull` (evals/.env.local), which the
 * runner loads here so users don't need a dotenv wrapper.
 */
export function ensureSandboxAuth(evalsRoot: string): void {
  if (process.env.VERCEL_OIDC_TOKEN) return;
  const envFile = join(evalsRoot, ".env.local");
  if (existsSync(envFile)) {
    for (const line of readFileSync(envFile, "utf8").split("\n")) {
      const match = /^VERCEL_OIDC_TOKEN="?([^"]+)"?$/.exec(line.trim());
      if (match) {
        process.env.VERCEL_OIDC_TOKEN = match[1];
        return;
      }
    }
  }
  throw new Error(
    "VERCEL_OIDC_TOKEN is not available. Run `vercel link` and `vercel env pull .env.local` in evals/ " +
      "(the token expires; re-pull when sandbox auth fails).",
  );
}

/**
 * Pack the working tree (not HEAD — uncommitted framework changes should be
 * what gets evaluated) for upload into sandboxes. Built once per run.
 */
export async function packRepo(repoRoot: string): Promise<string> {
  const tarball = join("/tmp", `zn-evals-repo-${process.pid}.tgz`);
  // Both bare and `*/`-prefixed patterns: BSD tar matches excludes against
  // whole paths, so "node_modules" alone would miss nested ones (and 200MB of
  // third_party/example caches would ride along).
  const excludes = [
    ".git",
    ".claude",
    ".vercel",
    "third_party",
    ".next",
    ".zig-cache",
    "zig-out",
    "node_modules",
    ".workspaces",
    "results",
    ".env.local",
    ".env*.local",
  ].flatMap((pattern) => ["--exclude", pattern, "--exclude", `*/${pattern}`, "--exclude", `*/${pattern}/*`]);
  const result = await exec("tar", ["-czf", tarball, ...excludes, "-C", repoRoot, "."], {
    cwd: repoRoot,
    timeoutMs: 5 * 60 * 1000,
  });
  if (result.code !== 0) throw new Error(`failed to pack repo: ${result.stderr.slice(0, 400)}`);
  return tarball;
}

/** Everything the sandbox needs before it can run the inner harness. */
const BOOTSTRAP = `set -euo pipefail
sudo dnf install -y -q xz
mkdir -p ${REPO_DIR} && tar xzf repo.tgz -C ${REPO_DIR} 2>/dev/null
ARCH=$(uname -m)
ZIG_URL=$(node -e "fetch('https://ziglang.org/download/index.json').then(r=>r.json()).then(j=>console.log(j['0.16.0'][process.argv[1]+'-linux'].tarball))" "$ARCH")
echo "installing zig from $ZIG_URL"
curl -sSL "$ZIG_URL" -o zig.tar.xz
mkdir -p zig && tar xJf zig.tar.xz -C zig --strip-components=1
sudo ln -sf /vercel/sandbox/zig/zig /usr/local/bin/zig
zig version
npm install --global --silent pnpm@10.23.0 @anthropic-ai/claude-code
claude --version
pnpm --version
cd ${REPO_DIR}/evals && pnpm install --frozen-lockfile
`;

export async function runCaseInSandbox(options: {
  evalCase: EvalCase;
  tarballPath: string;
  gatewayKey: string;
  model: string;
  judgeModel: string;
  vcpus: number;
  localResultsDir: string;
  log: (line: string) => void;
}): Promise<CaseResult> {
  const { evalCase, log } = options;
  log(`[sandbox] creating (${options.vcpus} vcpus, ${SANDBOX_TIMEOUT_MS / 60000}m timeout)...`);
  const sandbox = await Sandbox.create({
    runtime: "node24",
    resources: { vcpus: options.vcpus },
    timeout: SANDBOX_TIMEOUT_MS,
    env: { AI_GATEWAY_API_KEY: options.gatewayKey },
  });
  try {
    log(`[sandbox] ${sandbox.name || "created"}; uploading repo...`);
    await sandbox.writeFiles([
      { path: "repo.tgz", content: readFileSync(options.tarballPath) },
    ]);

    await run(sandbox, "bootstrap (zig + claude + pnpm install)", BOOTSTRAP, log, false);

    // The inner harness does the rest: repo-root zig build, scaffold + skill,
    // pre-warm, agent, graders (snapshot checks self-skip off-macOS), judge.
    // --skip-permissions is safe here: the whole VM is the throwaway.
    const inner = [
      "cd repo/evals &&",
      "pnpm eval --skip-permissions --keep-workspaces",
      `--model ${options.model} --judge-model ${options.judgeModel}`,
      evalCase.name,
    ].join(" ");
    // The inner harness prefixes its own lines with the case name; strip it
    // since our `log` adds the same prefix.
    const innerPrefix = `[${evalCase.name}] `;
    const innerLog = (line: string): void =>
      log(line.startsWith(innerPrefix) ? line.slice(innerPrefix.length) : line);
    const innerExit = await run(sandbox, `inner eval: ${evalCase.name}`, inner, innerLog, true);

    const stampCmd = await sandbox.runCommand("bash", ["-c", "ls -t repo/evals/results | head -1"]);
    const stamp = (await stampCmd.stdout()).trim();
    if (!stamp) throw new Error("inner run produced no results directory");
    const resultBuffer = await sandbox.readFileToBuffer({
      path: `repo/evals/results/${stamp}/${evalCase.name}/result.json`,
    });
    if (!resultBuffer) {
      throw new Error(`inner run exited ${innerExit} without writing result.json`);
    }
    const caseResult = JSON.parse(resultBuffer.toString("utf8")) as CaseResult;
    caseResult.workspace = `vercel-sandbox:${sandbox.name || "unknown"}`;

    const { mkdirSync, writeFileSync } = await import("node:fs");
    mkdirSync(options.localResultsDir, { recursive: true });
    writeFileSync(
      join(options.localResultsDir, "result.json"),
      `${JSON.stringify(caseResult, null, 2)}\n`,
    );
    const transcript = await sandbox.readFileToBuffer({
      path: `repo/evals/results/${stamp}/${evalCase.name}/transcript.jsonl`,
    });
    if (transcript) writeFileSync(join(options.localResultsDir, "transcript.jsonl"), transcript);
    return caseResult;
  } finally {
    log("[sandbox] stopping");
    await sandbox.stop().catch(() => undefined);
  }
}

/** Run a bash script in the sandbox, streaming output lines through `log`. */
async function run(
  sandbox: Sandbox,
  label: string,
  script: string,
  log: (line: string) => void,
  allowFailure: boolean,
): Promise<number> {
  const command = await sandbox.runCommand({
    cmd: "bash",
    args: ["-c", script],
    detached: true,
  });
  let buffered = "";
  for await (const entry of command.logs()) {
    buffered += entry.data;
    let newline;
    while ((newline = buffered.indexOf("\n")) !== -1) {
      const line = buffered.slice(0, newline).trimEnd();
      buffered = buffered.slice(newline + 1);
      if (line) log(line);
    }
  }
  if (buffered.trim()) log(buffered.trim());
  const finished = await command.wait();
  const exitCode = finished.exitCode ?? -1;
  if (exitCode !== 0 && !allowFailure) {
    throw new Error(`sandbox step failed (${label}): exit ${exitCode}`);
  }
  return exitCode;
}
