# Claude Notch

Live status of your Claude sessions, in the MacBook notch.

Hover the notch to see every Claude Code and Claude desktop session at a glance. The notch also drops down on its own when a session needs you, finishes, or is about to lose its prompt cache, and it can show **Allow / Deny** buttons for permission prompts so you can answer without switching windows.

- Works with **Claude Code in the terminal** and **Claude Code in the Claude desktop app**.
- Runs entirely on your Mac. No network access, no account, nothing is sent anywhere.
- One small native app (Swift / SwiftUI). No dependencies.

## What you get

| | |
|---|---|
| **Resting state** | Two small wings beside the notch: a pulsing sparkle while something is working, and on the right the most important number — sessions that need you, the nearest cache countdown, or a green dot for "all quiet". |
| **Alerts** (with a sound) | A session **needs you** (permission prompt, question, plan to approve) · a session **finished** · a **prompt cache is about to expire** · a cache **went cold**. |
| **Hover** | One card per session: state, what it is doing right now, a **cache countdown ring**, and **context-window usage** (`212k / 1M · 21%`). |
| **Click a card** | Opens that session in the Claude desktop app. For terminal sessions it copies `claude --resume <id>` instead. |
| **Quiet mode** | Disappears completely while a full-screen app (a film, a presentation) is in front: no sound, no drop-downs, nothing drawn. Or pause alerts for an hour by hand. |
| **Approvals** | Permission prompts appear as cards with the command, a risk flag for things like `rm -rf`, and **Deny / Allow** buttons. Several sessions can wait at once. |

## Requirements

- macOS 14 (Sonoma) or newer. A notch is not required; on other Macs it draws a notch-sized pill at the top centre.
- The Xcode command line tools, to build it (`xcode-select --install`). Full Xcode is only needed to run the tests.
- Claude Code (terminal) and/or the Claude desktop app, already used at least once.

## Quick start

```bash
git clone <this repository> claude-notch      # or just copy the folder
cd claude-notch
./scripts/install.sh
```

That builds the app, installs it, adds the hooks and starts it. Add `--login` to start it automatically when you log in:

```bash
./scripts/install.sh --login
```

Then **restart any Claude sessions that were already open**: Claude reads its hooks when a session starts, so older sessions keep working but only get the "guessed" behaviour described below until restarted.

Hover the notch. That's it.

### What the installer changes on your machine

| What | Where |
|---|---|
| The app and its data | `~/.claude-notch/` (private to your user, mode 700) |
| Seven hook entries (`Notification`, `Stop`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SessionEnd`, `PermissionRequest`) | `~/.claude/settings.json` |
| A one-time backup of your original settings | `~/.claude/settings.json.notch-backup` |
| A login item (only with `--login`) | `~/Library/LaunchAgents/com.claude-notch.app.plist` |

The hook installer only ever adds or removes entries that run its own two scripts. All your other settings and hooks are preserved, and it refuses to touch a `settings.json` it cannot parse.

Other options: `--no-hooks` (skip editing settings.json; the notch still works, with the limitations below), `--no-start`, `--help`.

## Using it

**Resting.** The sparkle on the left turns amber when something needs you. The right wing shows, in priority order: an amber number (sessions needing you), a countdown (a cache is close to expiring), the number of working sessions, or a green dot.

**Alerts.** The notch drops down for a few seconds with a sound:

| Alert | When |
|---|---|
| Needs you | A permission prompt, a question, or a plan is waiting |
| Finished | A session that was working just completed |
| Cache low | 1 minute left on a 5-minute cache, or 5 minutes on a 1-hour cache |
| Cache cold | The cache just expired; your next message re-reads the whole context |

Alerts are skipped while your pointer is on the notch, and while quiet mode is active (below).

**The list.** Sessions are sorted: needs you, working, done, idle. Each card has:

- the **ring**: time left on the prompt cache. Green is fresh, amber is half gone, red is nearly out, a snowflake means cold. While a session works it shows animated dots.
- the **state** label and what the session is doing (`Bash: swift build`, `Waiting to run …`, or its last words).
- the **context bar**: tokens used out of the model's window.

Right-click the list to quit.

**Approvals.** When Claude asks to run a tool, the notch shows the request. Allow and Deny answer Claude directly. "Ask in app" hands the prompt back to Claude's own dialog, and so does doing nothing for about 110 seconds, closing the notch app, or answering in Claude first. Questions and plan approvals are never intercepted: they need Claude's full interface.

Allow does not override your deny rules or Claude's other safeguards. It answers the same prompt you would have clicked yourself, so treat it like clicking Allow.

## Quiet mode

Right-click the session list for the controls:

- **Stay quiet in full screen** (on by default). While a full-screen app is in front, the notch draws nothing, plays no sounds and lets every click through. When you leave full screen it returns, and any approval still waiting is shown.
- **Pause alerts for 1 hour.** No sounds and no automatic drop-downs; the resting wings stay visible, with a small bell-slash icon, so you can still see state at a glance. **Resume alerts** ends it early.

Approvals that arrive while quiet are not lost: they wait, and if you are still away after about 110 seconds they go back to Claude's own dialog.

Full screen is detected from the system's own "an app is full screen" flag. A few players draw their own full-screen mode without setting it; if the notch still shows over one, use **Pause alerts**.

## How it works

```
 ~/.claude/projects/**/*.jsonl ──┐                          ┌──> collapsed wings
   (session transcripts)         │                          │
                                 ├─> SessionMonitor ──> NotchModel ──> alerts (peek)
 ~/.claude-notch/state/*.json ───┘   (state inference)      │          └──> session list
   (hook events, exact)                                      │
                                                             └──> approval cards
 Claude Code ──PermissionRequest hook──> requests/ ─> PermissionBroker ─> responses/ ──> Claude Code
```

**Transcripts.** Claude Code writes every session to a `.jsonl` file. The app reads the last few hundred KB of each recent file once or twice a second. From that it works out the session's title, last activity, model, context usage and cache timing. Transcripts can reach hundreds of MB, so only the tail is read, widening if the end holds only metadata.

**Hooks.** Claude Code can run a script on events. The app installs two:

- `notch-hook.sh` records the latest event per session in `~/.claude-notch/state/`. This is how "needs you" is exact: the `Notification` event fires the instant Claude asks for input. Without hooks the app *guesses*: a tool call left pending for 8 seconds is assumed to be waiting on you, which a slow command can trigger by mistake.
- `notch-permission.sh` implements the approval buttons. It writes the request to `requests/`, waits for the app's answer in `responses/`, and prints it for Claude Code. If the app isn't running (checked via a heartbeat file), it prints nothing and Claude shows its normal dialog, so the notch can never block a session.

**Prompt cache timer.** The API reports no expiry time, so this is estimated: the lifetime (5 minutes or 1 hour) comes from the most recent request that *wrote* to the cache, and the clock starts when that request *started*, not when its reply finished. Any request that reads the cache refreshes it. Treat the countdown as accurate to within seconds in normal use, not as a guarantee: the cache can be evicted early or invalidated by changing tools or the system prompt.

**Context usage.** `input + cache read + cache creation + output` tokens of the last reply, which matches `/context` in Claude Code. The window is 1M tokens for the Fable, Mythos and 5-generation models and for Opus/Sonnet 4.6+, 200k for older ones. Right after `/compact` the figure is an estimate and is marked with `~` until the next reply.

**Opening a session.** The Claude desktop app keeps its own session id next to each transcript id. The app looks that up and opens `claude://code/continue?session=…`.

## Limitations

- "Needs you" is guessed for sessions started before the hooks were installed (restart them).
- A session that has been silent for 5+ minutes inside one very long operation shows as idle.
- The cache countdown is an estimate (see above). The context figure is a snapshot of the last reply and does not include a prompt you have just typed.
- Clicking a card needs the Claude desktop app, with its "entry points" setting on. Terminal sessions get a copied resume command instead.
- The deep link format and the desktop app's session metadata are internal to Claude and may change; if they do, clicking falls back to the resume command.
- The risk flag is a simple pattern match on shell commands. It is a nudge, not a security boundary.
- Full-screen detection depends on the system flag described under Quiet mode; use Pause alerts for players that don't set it.
- Only the display with the notch is used. On a Mac without one the pill sits at the top centre of the main display.

## Configuration

| Setting | Effect |
|---|---|
| `CLAUDE_CONFIG_DIR` | Where Claude Code keeps its files (default `~/.claude`). Set it for the install, and the app and hooks follow. |
| `CLAUDE_NOTCH_HOME` | Where the app keeps its data (default `~/.claude-notch`). |
| `CLAUDE_NOTCH_EXPANDED=1` | Start with the list open (useful for screenshots). |

Timings, thresholds and window sizes all live in one file, [`Sources/NotchCore/Config.swift`](Sources/NotchCore/Config.swift). Rebuild with `./scripts/install.sh` after changing it.

## Troubleshooting

Start with:

```bash
~/.claude-notch/bin/ClaudeNotch status
```

It shows whether transcripts are found, which hooks are installed and whether the app is running.

| Problem | Try |
|---|---|
| Nothing at the top of the screen | `status` should say "running". If not, run `~/.claude-notch/bin/ClaudeNotch` in a terminal and read any error. |
| "Transcripts NOT FOUND" | Use Claude Code or the desktop app once. If your config is elsewhere, set `CLAUDE_CONFIG_DIR` and reinstall. |
| The list is empty or missing a session | Only sessions active in the last 12 hours are shown. |
| "Needs you" is late or wrong | Run `status`. If hooks aren't installed, `./scripts/install.sh`. Then restart the Claude session. |
| No Allow/Deny buttons | Hooks must be installed *and* the session started after that. The app must be running. Check that `~/.claude/settings.json` has a `PermissionRequest` entry. |
| Clicking a card does nothing | Needs the Claude desktop app and its entry-points setting. For terminal sessions the command is on your clipboard. |
| Wrong display | The notch goes on the screen that has a notch, else the main display. Restart the app after connecting a display. |
| Hooks seem to slow Claude down | They are tiny shell scripts and only the approval hook ever waits, and only while the app is running and you could answer. `./scripts/uninstall.sh` removes everything. |

## Uninstall

```bash
./scripts/uninstall.sh
```

Stops the app, removes its hooks from `settings.json` (everything else there is untouched), removes the login item and deletes `~/.claude-notch`. Use `--keep-data` to keep the data directory.

## Privacy and security

- The app only reads local files (Claude's transcripts and its own data directory) and never opens a network connection.
- Hook state files hold what Claude Code passes to hooks, including commands and file paths. They live in `~/.claude-notch/`, which is private to your user, and are deleted when a session ends.
- The permission hook can approve tool calls on your behalf only when you click Allow. It never approves anything by itself, and falls back to Claude's own dialog whenever the app can't answer.
- No telemetry, and no updates are fetched.

## Development

```
Sources/
  NotchCore/            Everything that isn't UI (importable, fully tested)
    Config.swift          every tunable number
    Paths.swift           every file location, injectable for tests
    Models/               ClaudeSession, PermissionRequest, NotchGeometry
    Transcript/           reading, folding and interpreting transcripts
    Services/             SessionMonitor, PermissionBroker, AlertEngine, SessionLinker
    Hooks/                HookInstaller + the embedded hook scripts
    Support/              formatting, tool descriptions, risk flags
  ClaudeNotch/          The app: panel, view model, SwiftUI views, command-line commands
Tests/NotchCoreTests/   106 unit tests, including real runs of the hook scripts
scripts/                install.sh, uninstall.sh
```

```bash
make test          # swift test
make run           # run from the build folder
make status        # same as `ClaudeNotch status`
```

Design notes that are easy to forget:

- The panel is a non-activating, borderless window, so it never steals focus. SwiftUI's hover callbacks are unreliable in such a window, so while the list is open the pointer is polled directly and mapped to a card in `NotchGeometry` (which is tested). Views observe the model with `@ObservedObject` so they redraw when it changes.
- Transcripts are append-only and large. Always read the tail only, and ignore housekeeping lines (`/compact` summaries, command echoes, metadata) when deciding what a session is doing. Their timestamps are not activity.
- The hook scripts are embedded in `HookScripts.swift` so one binary can install them anywhere. The shell tests in `PermissionBrokerTests.swift` run them for real.

## Credits

Built with Claude Code. Claude and Claude Code are products of Anthropic; this project is unofficial and not affiliated with or endorsed by Anthropic.
