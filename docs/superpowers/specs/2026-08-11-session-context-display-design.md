# Session context display

## Problem

The session list and preview pane don't tell you what a session was about or where you
left off. Rows show the last user message; the preview shows the first user message plus
tail messages. Both are raw transcript fragments. With ~1,100 sessions, finding the one
you want means opening several and reading.

## Key finding

Claude Code already writes an auto-generated title into each session's JSONL. The TUI
never reads it. Three record types matter:

```json
{"type":"ai-title","aiTitle":"Fix flaky auth token refresh test","sessionId":"..."}
{"type":"custom-title","customTitle":"cc-sessions","sessionId":"..."}
{"type":"last-prompt","lastPrompt":"does the fix cover concurrent callers...","leafUuid":"..."}
```

Coverage across 1,090 sessions measured 2026-08-07:

| Bucket | `ai-title` | `last-prompt` |
|---|---|---|
| Newest 100 | 72% | 100% |
| 101-300 | 80% | 100% |
| 301-600 | 43% | 99.7% |
| 601+ (to 2026-07-08) | 34% | 98.2% |

The `ai-title` gap is feature age, not a data problem; coverage improves on its own.
Compaction summaries (`isCompactSummary`) exist in only 21 files and are not used.

Claude Code stops regenerating `ai-title` partway through a session (median position of
the last such record is 50% through the file), so the title reflects the session's early
direction. It is a topic label, not a stopping point. "Where I left off" comes from
`last-prompt` plus the last assistant text block.

## Scope

Two features, shipped in order:

- **A.** Read what Claude Code already stores; restructure the row label and preview.
  Zero tokens, zero user action.
- **B.** On-demand Haiku summary for a single selected session, saved to disk.

## A. Extraction and display

### Extraction layer

One function, `extract_session_meta(path) -> dict`, replaces the ad-hoc head-50 /
tail-30 reads inside `load_sessions()`. Fields:

| Field | Source |
|---|---|
| `ai_title` | last `ai-title` record |
| `custom_title` | last `custom-title` record |
| `last_prompt` | last `last-prompt` record |
| `last_assistant` | last assistant `text` block (tail read) |
| `first_msg` | first user text (existing logic) |
| `files_touched` | `file-history-delta.trackingPath`, deduped, in order |
| `git_branch` | `gitBranch` on the last system/assistant record |
| `message_count` | `messageCount` on the last `turn_duration` system record |
| `duration` | last timestamp minus first timestamp |
| `model` | `message.model` on the last assistant record |

`ai-title`, `custom-title`, and `last-prompt` records sit anywhere in the file, so
extraction is a full-file pass with a byte-substring prefilter before `json.loads`.
Measured at 1.9s for all 1,179 session files, so a cold cache build is acceptable and a
warm launch does no scanning at all.

`files_touched` uses `file-history-delta.trackingPath` rather than parsing `tool_use`
blocks: one field per record, no nested traversal.

### Cache

`~/.config/cc-sessions/session-cache.json`, keyed by session id. Each entry stores the
extracted fields plus the `(mtime, size)` the extraction was based on. On launch, any
session whose current `(mtime, size)` differs is re-extracted; the rest are read from
cache. Corrupt or unreadable cache falls back to a full rebuild.

### Row label

Title-primary. Size in bytes is dropped from the row (it is dominated by tool results
and misrepresents session length); `message_count` carries that role in the preview.

```
 2h ago  Fix flaky auth token refresh test
          ↳ does the fix cover concurrent callers or just
```

Label precedence, highest first:

1. Local name from `session-names.json`
2. `custom_title` (Claude Code `/rename`)
3. `ai_title`
4. Saved Haiku summary title (feature B)
5. `last_prompt` (current behavior, so nothing regresses)

### `/rename` source of truth

`custom-title` records make `history.jsonl` parsing redundant. The inline record becomes
the source; `load_claude_renames()` stays only as a fallback for sessions whose JSONL has
no `custom-title` record. This is a behavior change to existing rename handling.

### Preview pane

```
Fix flaky auth token refresh test
~/code/acme-api · main · 191 msgs · 1h 42m · fable-5

WHERE I LEFT OFF
> does the fix cover concurrent callers or just the single-refresh case
Only the single-refresh path. Concurrent callers still race...

FILES TOUCHED (4)
src/auth/refresh.py · tests/test_refresh.py · src/auth/__init__.py · CHANGELOG.md

STARTED WITH
the token refresh test fails about one run in twenty
```

File paths render relative to the session `cwd` where they fall under it, absolute
otherwise. Sections with no data are omitted rather than shown empty.

## B. On-demand Haiku summary

### Trigger

A keybinding on the selected session, plus a command palette entry. Runs against one
session only; there is no bulk or background path. Regenerating on an
already-summarized session overwrites the saved result.

### Invocation

```
claude -p --model haiku --safe-mode --setting-sources '' --strict-mcp-config \
  --tools '' --no-session-persistence --system-prompt '<summariser prompt>'
```

Reuses the Claude Code CLI the tool already requires, and its OAuth, so no API key and no
new dependency. The isolation flags matter: without them the invocation takes 10.7s and
picks up the user's `CLAUDE.md`, hooks, and MCP servers, which contaminate the output.
With them it returns in 2.3s clean. `--bare` is not usable; it refuses OAuth and requires
`ANTHROPIC_API_KEY`.

### Input construction

User prompts and assistant `text` blocks only. Tool calls and tool results are dropped;
they are most of the bytes and little of the meaning. Head and tail are capped by
character budget with the middle elided, bounding cost on large sessions (p90 is 1 MB,
max observed 205 MB). A median 42 KB session costs a fraction of a cent.

### Output and storage

The model returns a short title and a few sentences on where the session ended. Saved to
`~/.config/cc-sessions/summaries.json`, keyed by session id, storing the title, the body,
and the `mtime` at generation time.

A saved summary persists indefinitely. It does not expire when the session changes. If
the session is later resumed and Claude Code writes a real `ai-title`, that title wins
for the row label per the precedence list, and the saved body remains available in the
preview until the user regenerates. This is the user's stated intent: a real Claude title
supersedes the generated one, otherwise the generated one is kept until explicitly
regenerated.

The saved summary appears in the preview above `WHERE I LEFT OFF`, marked as generated
and dated, so it is never confused with Claude Code's own title.

## Out of scope

- Bulk or background summarization of all sessions. On-demand only, by design.
- Special handling for automated sessions (goal-evaluator runs and similar) whose
  `last_prompt` is a wall of instruction text. They render truncated to row width exactly
  as they do today, and an `ai-title` or an on-demand summary fixes any that matter.
- Compaction summaries as a data source.

## Error handling

Extraction failures on a single session degrade that session to the fields that did
parse, never abort the scan; this matches the existing `try/except` posture in
`load_sessions()`. A failed or timed-out `claude -p` call surfaces a notification and
leaves any previously saved summary intact. The summariser runs on a Textual worker so
the UI stays responsive, with the row showing a pending state while it runs.

## Testing

Extraction is a pure function over a file path, so it is testable against fixture JSONL
files: one with `ai-title`, one with only `custom-title`, one with neither, one with
malformed lines, one empty. Label precedence is a pure function over the extracted dict
and gets a table-driven test. Cache invalidation is tested by mutating `(mtime, size)`.
The `claude -p` call is behind a seam that tests stub out.
