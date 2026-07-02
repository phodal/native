/** Per-case configuration, loaded from `cases/<name>/eval.json`. */
export interface EvalCase {
  /** Case name; must match the directory name. */
  name: string;
  /** Short human description of what the case exercises. */
  description: string;
  /** The task prompt handed to the agent-under-test. Describes app requirements, never the solution. */
  prompt: string;
  /** Scaffold frontend passed to `zero-native init --frontend <frontend>`. */
  frontend: "native";
  /** Wall-clock budget for the agent run, in milliseconds. */
  timeoutMs: number;
  /** `--max-turns` for the claude invocation. */
  maxTurns: number;
  /** Deterministic graders, run in order after the agent finishes. */
  checks: CheckSpec[];
}

export type CheckSpec =
  | BuildTestCheck
  | MarkupCheckCheck
  | FileGrepCheck
  | SnapshotGrepCheck
  | LlmJudgeCheck;

/** Run `zig build test <args>` in the workspace. */
export interface BuildTestCheck {
  type: "build_test";
  /** Extra args, e.g. ["-Dplatform=null"]. */
  args?: string[];
}

/** Run `zero-native markup check` on every `src/**\/*.zml` in the workspace. */
export interface MarkupCheckCheck {
  type: "markup_check";
}

/** Grep workspace files for a pattern. */
export interface FileGrepCheck {
  type: "file_grep";
  /** Glob-ish file selector relative to the workspace: exact path or "src/*.zml". */
  files: string;
  /** JavaScript regular expression source (no flags; matched with "m"). */
  pattern: string;
  /** true = pattern must appear in at least one selected file; false = must appear in none. */
  expect: boolean;
  description: string;
}

/**
 * Build the workspace app with `-Dautomation=true`, launch it, wait for the
 * automation server, then grep the widget snapshot. macOS-local only; skipped
 * (reported as "skipped", not passed) when --skip-live is set.
 */
export interface SnapshotGrepCheck {
  type: "snapshot_grep";
  /** Each JavaScript regexp source must match somewhere in snapshot.txt. */
  patterns: string[];
  description: string;
}

/**
 * Grade quality dimensions the deterministic checks can't see (idiomatic
 * Model/Msg design, template factoring, test meaningfulness) with a judge
 * model called directly through the AI Gateway. Advisory by default: the
 * score is recorded and printed but never fails the case. Skipped in
 * --dry-run (no model calls).
 */
export interface LlmJudgeCheck {
  type: "llm_judge";
  /** Case-specific criteria, each scored 0-10 by the judge. */
  criteria: string[];
  /** Workspace files to show the judge (default: src/*.zml, src/main.zig, src/tests.zig). */
  files?: string[];
  /** Overall score at or above this counts as pass. Default 6. */
  minScore?: number;
  /** When false, an overall score below minScore fails the case. Default true. */
  advisory?: boolean;
  description: string;
}

export interface CheckResult {
  type: CheckSpec["type"];
  description: string;
  status: "pass" | "fail" | "skipped";
  /** Trimmed evidence: failing command output tail, missing pattern, etc. */
  detail?: string;
  /** llm_judge only: the judge's overall 0-10 score. */
  score?: number;
  /** llm_judge only: a failing advisory check does not fail the case. */
  advisory?: boolean;
  durationMs: number;
}

export interface AgentRunResult {
  status: "completed" | "timeout" | "error" | "dry_run";
  model: string;
  numTurns?: number;
  totalCostUsd?: number;
  durationMs: number;
  sessionId?: string;
  /** Path to the captured stream-json transcript. */
  transcriptPath?: string;
  errorDetail?: string;
}

export interface CaseResult {
  case: string;
  /** 1-based trial number; only present when the run had --trials > 1. */
  trial?: number;
  workspace: string;
  startedAt: string;
  dryRun: boolean;
  agent: AgentRunResult;
  checks: CheckResult[];
  passed: boolean;
}

/** Per-check aggregation across the trials of one case (--trials > 1). */
export interface CheckAggregate {
  type: CheckSpec["type"];
  description: string;
  pass: number;
  fail: number;
  skipped: number;
  /** llm_judge only: mean of the recorded overall scores. */
  meanScore?: number;
}

/**
 * Aggregated result for one case across N independent trials, written to
 * results/<stamp>/<case>/aggregate.json (per-trial result.json files live in
 * results/<stamp>/<case>/trial-<n>/). Only produced when --trials > 1.
 */
export interface CaseAggregate {
  case: string;
  trials: number;
  /** Trials where every non-advisory check passed and the agent completed. */
  passedTrials: number;
  checks: CheckAggregate[];
  /** Mean of all recorded llm_judge overall scores across trials. */
  meanJudgeScore?: number;
  meanTurns?: number;
  totalCostUsd?: number;
  /** Sum of per-trial durations (agent + checks); trials may overlap in wall-clock. */
  totalDurationMs: number;
  results: CaseResult[];
}

export interface RunnerOptions {
  repoRoot: string;
  evalsRoot: string;
  caseNames: string[];
  model: string;
  judgeModel: string;
  dryRun: boolean;
  skipLive: boolean;
  skipPermissions: boolean;
  keepWorkspaces: boolean;
  /** Independent trials per case (own workspace, agent run, checks, judge). Default 1. */
  trials: number;
  /** Cases run concurrently up to this limit (default 2 local, all in sandbox mode). */
  concurrency: number | undefined;
  /** Run each case in its own Vercel Sandbox microVM instead of locally. */
  sandbox: boolean;
  sandboxVcpus: number;
}
