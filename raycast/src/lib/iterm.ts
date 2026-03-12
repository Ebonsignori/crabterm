import { execSync } from "child_process";

export function focusSession(sessionId: string): void {
  const script = `
    tell application "iTerm2"
      activate
      repeat with w in windows
        tell w
          repeat with t in tabs
            tell t
              repeat with s in sessions
                if (unique ID of s) is "${sessionId}" then
                  select t
                  select s
                  return
                end if
              end repeat
            end tell
          end repeat
        end tell
      end repeat
    end tell
  `;
  try {
    execSync(`osascript -e '${script.replace(/'/g, "'\"'\"'")}'`, { timeout: 5000 });
  } catch {
    // iTerm2 may not be running
  }
}

export function getActiveSessions(): Set<string> {
  const script = `
    tell application "iTerm2"
      set allIDs to {}
      repeat with w in windows
        tell w
          repeat with t in tabs
            tell t
              repeat with s in sessions
                set end of allIDs to (unique ID of s)
              end repeat
            end tell
          end repeat
        end tell
      end repeat
      set AppleScript's text item delimiters to ","
      return allIDs as text
    end tell
  `;
  try {
    const result = execSync(`osascript -e '${script.replace(/'/g, "'\"'\"'")}'`, {
      encoding: "utf-8",
      timeout: 5000,
    }).trim();
    if (!result) return new Set();
    return new Set(result.split(",").map((s) => s.trim()));
  } catch {
    return new Set();
  }
}

export function isItermRunning(): boolean {
  try {
    const result = execSync('pgrep -x "iTerm2" 2>/dev/null', { encoding: "utf-8" }).trim();
    return result.length > 0;
  } catch {
    return false;
  }
}
