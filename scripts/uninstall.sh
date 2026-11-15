#!/bin/bash
# Removes Claude Notch: stops it, takes its hooks out of Claude Code's settings.json, deletes the login item and its files.
# Everything else in settings.json is left alone.
#
#   ./scripts/uninstall.sh              remove everything
#   ./scripts/uninstall.sh --keep-data  keep ~/.claude-notch (the installed binary and state files)
set -euo pipefail

LABEL="com.claude-notch.app"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOTCH_HOME="${CLAUDE_NOTCH_HOME:-$HOME/.claude-notch}"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

keep=0
for arg in "$@"; do
  case "$arg" in
    --keep-data) keep=1 ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 64 ;;
  esac
done

step() { printf '\033[1m==> %s\033[0m\n' "$*"; }

step "Stopping"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
pkill -x ClaudeNotch 2>/dev/null || true

step "Removing hooks from Claude Code's settings.json"
binary=""
for candidate in "$NOTCH_HOME/bin/ClaudeNotch" "$ROOT/.build/release/ClaudeNotch"; do
  if [ -x "$candidate" ]; then binary="$candidate"; break; fi
done
if [ -n "$binary" ]; then
  # If this fails, stop before deleting the scripts: settings.json would be left pointing at files that no longer exist.
  "$binary" uninstall-hooks || {
    echo "Hooks were NOT removed, so nothing else was deleted. Fix the problem above and run this again." >&2
    exit 1
  }
else
  echo "Could not find the ClaudeNotch binary. If you installed hooks, remove the entries mentioning 'notch-hook.sh' and 'notch-permission.sh' from ~/.claude/settings.json by hand."
fi

step "Removing the login item"
rm -f "$AGENT"

if [ "$keep" -eq 0 ]; then
  step "Deleting $NOTCH_HOME"
  rm -rf "$NOTCH_HOME"
fi

echo "Done. (A backup of your original settings, if one was made, is ~/.claude/settings.json.notch-backup.)"
