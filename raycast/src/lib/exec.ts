import { execSync, exec } from "child_process";
import { existsSync } from "fs";

let resolvedCrabPath: string | null = null;

function expandHome(p: string): string {
  if (p.startsWith("~/")) return `${process.env.HOME}${p.slice(1)}`;
  return p;
}

function findCrab(): string {
  if (resolvedCrabPath) return resolvedCrabPath;

  // Check the repo source script directly (common dev setup)
  const repoScript = `${process.env.HOME}/Projects/crabterm/src/crabterm`;

  // Check common locations
  const candidates = [
    repoScript,
    "/usr/local/bin/crab",
    "/opt/homebrew/bin/crab",
    `${process.env.HOME}/bin/crab`,
    `${process.env.HOME}/.local/bin/crab`,
  ];

  for (const c of candidates) {
    if (existsSync(c)) {
      resolvedCrabPath = c;
      return c;
    }
  }

  // Try resolving via zsh (handles aliases and functions)
  try {
    const output = execSync("zsh -ilc 'which crab' 2>/dev/null", { encoding: "utf-8" }).trim();
    // `which` may return "crab: aliased to ~/Projects/crabterm/src/crabterm"
    const aliasMatch = output.match(/aliased to (.+)$/);
    if (aliasMatch) {
      const resolved = expandHome(aliasMatch[1].trim());
      if (existsSync(resolved)) {
        resolvedCrabPath = resolved;
        return resolved;
      }
    }
    // Or a plain path
    if (output && !output.includes(":") && existsSync(output)) {
      resolvedCrabPath = output;
      return output;
    }
  } catch {
    // fall through
  }

  throw new Error("Could not find `crab` binary. Ensure crabterm is installed and in your PATH.");
}

const SHELL_ENV = {
  ...process.env,
  PATH: `/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${process.env.PATH || ""}`,
};

export function runCrabSync(args: string): string {
  const crab = findCrab();
  return execSync(`/bin/bash "${crab}" ${args}`, {
    encoding: "utf-8",
    timeout: 30000,
    env: SHELL_ENV,
  }).trim();
}

export function runCrabAsync(args: string): Promise<string> {
  const crab = findCrab();
  return new Promise((resolve, reject) => {
    exec(
      `/bin/bash "${crab}" ${args}`,
      {
        encoding: "utf-8",
        timeout: 30000,
        env: SHELL_ENV,
      },
      (error, stdout, stderr) => {
        if (error) {
          reject(new Error(stderr || error.message));
        } else {
          resolve(stdout.trim());
        }
      },
    );
  });
}

export function getGitBranch(dir: string): string {
  try {
    return execSync(`git -C "${dir}" rev-parse --abbrev-ref HEAD 2>/dev/null`, {
      encoding: "utf-8",
      timeout: 5000,
    }).trim();
  } catch {
    return "unknown";
  }
}
