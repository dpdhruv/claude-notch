import Foundation

/// The two shell scripts Claude Code runs. They are embedded here (rather than shipped as loose files) so the single
/// binary can install them anywhere. Both locate their data directory relative to their own path.
enum HookScripts {
    static let recorderName = "notch-hook.sh"
    static let permissionName = "notch-permission.sh"

    /// Records the latest hook event per session, so the notch knows the exact state instead of guessing.
    static let recorder = #"""
    #!/bin/bash
    # Claude Notch: records the latest Claude Code hook event for each session.
    # Usage: notch-hook.sh <EventName>   (the hook's JSON arrives on stdin)
    umask 077   # state files contain the commands Claude runs; keep them private to you
    base="$(cd "$(dirname "$0")/.." && pwd)"
    dir="$base/state"; mkdir -p "$dir"

    payload=$(cat)
    # First session_id only, restricted to safe characters: it becomes a file name.
    sid=$(printf '%s' "$payload" | grep -o '"session_id" *: *"[A-Za-z0-9_-]*"' | head -1 | sed 's/.*"\([A-Za-z0-9_-]*\)"$/\1/')
    [ -z "$sid" ] && exit 0

    if [ "$1" = "SessionEnd" ]; then rm -f "$dir/$sid.json"; exit 0; fi

    tmp="$dir/.$sid.$$"
    printf '{"event":"%s","ts":%s,"payload":%s}\n' "$1" "$(date +%s)" "${payload:-null}" > "$tmp" && mv "$tmp" "$dir/$sid.json"
    exit 0
    """#

    /// Hands a permission prompt to the notch and waits for Allow or Deny.
    /// Prints nothing (so Claude Code shows its own dialog) whenever the notch can't answer.
    static var permission: String {
        #"""
    #!/bin/bash
    # Claude Notch: PermissionRequest hook.
    umask 077
    base="$(cd "$(dirname "$0")/.." && pwd)"
    requests="$base/requests"; responses="$base/responses"; heartbeat="$base/alive"
    payload=$(cat)

    # The app refreshes the heartbeat every couple of seconds; without it, never intercept.
    [ -f "$heartbeat" ] || exit 0
    age() { echo $(( $(date +%s) - $(stat -f %m "$heartbeat" 2>/dev/null || echo 0) )); }
    [ "$(age)" -gt \#(Config.heartbeatMaxAge) ] && exit 0

    # Questions and plan approvals need Claude's full UI.
    printf '%s' "$payload" | grep -Eq '"tool_name" *: *"(AskUserQuestion|ExitPlanMode)"' && exit 0

    mkdir -p "$requests" "$responses"
    id="$(date +%s)-$$"
    trap 'rm -f "$requests/$id.json" "$responses/$id.json"' EXIT TERM INT HUP
    tmp="$requests/.$id.tmp"
    printf '{"id":"%s","pid":%s,"ts":%s,"payload":%s}\n' "$id" "$$" "$(date +%s)" "${payload:-null}" > "$tmp" && mv "$tmp" "$requests/$id.json"

    # Wait for the app's answer. Time-based (SECONDS), so it ends when the app's countdown does,
    # comfortably before the hook's own timeout.
    deadline=$(( SECONDS + \#(Int(Config.permissionHandoff)) ))
    while [ "$SECONDS" -lt "$deadline" ]; do
      if [ -f "$responses/$id.json" ]; then
        out=$(cat "$responses/$id.json")
        [ "$out" != "PASS" ] && printf '%s' "$out"
        exit 0
      fi
      [ "$(age)" -gt \#(Config.heartbeatMaxAge) ] && exit 0   # the app quit: fall back to Claude's dialog
      sleep 0.2
    done
    exit 0
    """#
    }
}
