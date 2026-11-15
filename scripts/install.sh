#!/bin/bash
# Builds Claude Notch, installs it, wires up Claude Code's hooks and starts it.
#
#   ./scripts/install.sh              build, install, add hooks, start
#   ./scripts/install.sh --login      ...and start automatically when you log in
#   ./scripts/install.sh --no-hooks   skip editing Claude Code's settings.json (the notch then works from transcripts alone)
#   ./scripts/install.sh --no-start   install but don't launch
#
# Safe to re-run: it upgrades in place.
set -euo pipefail

LABEL="com.claude-notch.app"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOTCH_HOME="${CLAUDE_NOTCH_HOME:-$HOME/.claude-notch}"
BIN="$NOTCH_HOME/bin/ClaudeNotch"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

login=0; hooks=1; start=1
for arg in "$@"; do
  case "$arg" in
    --login) login=1 ;;
    --no-hooks) hooks=0 ;;
    --no-start) start=0 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 64 ;;
  esac
done

step() { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- Requirements ----------------------------------------------------------------------------------------------
[ "$(uname)" = "Darwin" ] || die "Claude Notch is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || die "macOS 14 or newer is required (this is $(sw_vers -productVersion))."
command -v swift >/dev/null || die "Swift not found. Install the Xcode command line tools:  xcode-select --install"
[ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ] || warn "No Claude Code folder at ${CLAUDE_CONFIG_DIR:-$HOME/.claude} yet. The notch will stay empty until you have used Claude Code or the Claude desktop app."

# ---- Build -----------------------------------------------------------------------------------------------------
step "Building (first build takes a minute)"
(cd "$ROOT" && swift build -c release --product ClaudeNotch 2>&1 | tail -n 3)
BUILT="$(cd "$ROOT" && swift build -c release --show-bin-path)/ClaudeNotch"
[ -x "$BUILT" ] || die "Build did not produce $BUILT"

# ---- Install ---------------------------------------------------------------------------------------------------
step "Installing to $NOTCH_HOME"
pkill -x ClaudeNotch 2>/dev/null || true; sleep 0.5
mkdir -p "$NOTCH_HOME/bin"
cp "$BUILT" "$BIN"

if [ "$hooks" -eq 1 ]; then
  step "Adding hooks to Claude Code's settings.json"
  "$BIN" install-hooks
else
  warn "Skipping hooks: 'needs you' is then a guess, and approvals can't be answered from the notch."
fi

# ---- Start at login (optional) ---------------------------------------------------------------------------------
if [ "$login" -eq 1 ]; then
  step "Starting at login"
  mkdir -p "$(dirname "$AGENT")"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLAUDE_CONFIG_DIR</key><string>${CLAUDE_CONFIG_DIR:-}</string>
    <key>CLAUDE_NOTCH_HOME</key><string>${CLAUDE_NOTCH_HOME:-}</string>
  </dict>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$AGENT"
fi

# ---- Start -----------------------------------------------------------------------------------------------------
if [ "$start" -eq 1 ]; then
  step "Starting"
  if [ "$login" -eq 1 ]; then
    launchctl kickstart -k "gui/$UID/$LABEL"
  else
    nohup "$BIN" >/dev/null 2>&1 &
    disown
  fi
  sleep 1
  pgrep -x ClaudeNotch >/dev/null && echo "Running. Look at the top of your screen." || warn "It did not stay running. Try:  $BIN"
fi

cat <<DONE

Done.
  - Restart any Claude sessions that were already open so they load the hooks.
  - Hover the notch to see your sessions.
  - Check on things any time with:  $BIN status
  - Remove everything with:         ./scripts/uninstall.sh
DONE
