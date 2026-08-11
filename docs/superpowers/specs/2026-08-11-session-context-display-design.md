# Session context display

## Problem

The session list and preview pane don't tell you what a session was about or where you
left off. Rows show the last user message; the preview shows the first user message plus
tail messages. Both are raw transcript fragments. With ~1,400 sessions, finding the one
you want means opening several and reading.

## Key finding

Claude Code already writes an auto-generated title into each session's JSONL. The TUI
never reads it. Three record types matter:

```json
{"type":"ai-title","aiTitle":"Fix flaky auth token refresh test","sessionId":"..."}
{"type":"custom-title","customTitle":"cc-sessions","sessionId":"..."}
{"type":"last-prompt","lastPrompt":"does the fix cover concurrent callers...","leafUuid":"..."}
```

**These records are always near the end of the file.** `ai-title` is rewritten
repeatedly as a session progresses (median 12 records per session, one every ~20 lines),
and the final one sits a median of 3 lines / 7 KB from EOF, worst case 28 lines / 31 KB.

Measured across all 1,391 sessions: a **128 KB tail read finds every `ai-title`,
`custom-title`, and `last-prompt` with zero misses and zero mismatches** against a
full-file scan, in **0.15s total**. `_read_tail_lines` already reads a 128 KB tail
(`cc-sessions-tui:231-246`), so extraction is nearly free and needs no cache and no
full-file scan.

Two consequences: the title is **current**, not a stale early-session label, because it
keeps regenerating to the end; and resuming a session produces a fresh `ai-title`, which
is what makes the summary-supersession rule below work.

Coverage across 1,391 sessions, by recency bucket:

| Bucket | `ai-title` | `last-prompt` |
|---|---|---|
| Newest 100 | 74% | 100% |
| 101-300 | 84% | 100% |
| 301-600 | 75% | 100% |
| 601+ | 43% | 99.7% |
| **All** | **58%** | **99.9%** |

The gap is feature age and improves on its own. Treat these as shape, not exact digits:
resuming a session rewrites its mtime and reshuffles the buckets, so an independent
recount on a different day lands within a few points either way. `ai_title` length is
median 45 chars, max 71, so it fits a row. Compaction summaries (`isCompactSummary`)
exist in 25 files and are not used.

Corpus composition matters for reading any of these numbers: **786 of 1,391 sessions are
under 10 lines**, single-turn automated runs (goal-evaluators and background jobs). They
dominate any whole-corpus median. Segmenting by session length is what exposes the
regeneration behavior above: median relative position of the last `ai-title` is 0.500 for
sessions under 20 lines but **0.995 for sessions over 300 lines**.

## Scope

- **A.** Read what Claude Code already stores; retitle rows, restructure the preview.
- **B.** On-demand Haiku summary for one selected session, saved to disk.

## A. Extraction and display

### Extraction

Extend the existing tail read in `load_sessions()` (`cc-sessions-tui:151`) rather than
adding a scan. `_read_tail_lines` keeps its 128 KB window; its `max_lines` cap is raised
so the whole window is parsed, since the records we need can be up to 28 lines from EOF.

| Field | Source (all within the 128 KB tail) |
|---|---|
| `ai_title` | last `ai-title` record |
| `custom_title` | last `custom-title` record |
| `last_prompt` | last `last-prompt` record **that has a `lastPrompt` field** |
| `last_assistant` | last assistant `text` block whose record is not `<synthetic>` |
| `git_branch` | `gitBranch` on the last user/assistant/system record |
| `files_edited` | union of `tool_use` Edit/Write/NotebookEdit `file_path` and `file-history-delta.trackingPath`, **normalized to absolute against `cwd` first** |

Three extraction details are not optional:

- **87 of 10,693 `last-prompt` records (0.8%) carry only `{type, leafUuid, sessionId}`**
  with no `lastPrompt` field. Taking the last record blindly yields `None` on those
  sessions; take the last record that actually has the field.
- **`message.model` is the literal string `<synthetic>` on the last assistant record in
  10.4% of sessions** (37% of all assistant records), emitted for interrupts and error
  messages. `model` is not displayed anywhere in this design, but `last_assistant` must
  skip synthetic records or the "where I left off" text becomes an interrupt notice one
  time in ten.
- **`file-history-delta.trackingPath` is cwd-relative when the file sits under the
  session `cwd` and absolute otherwise**, while `tool_use.file_path` is always absolute.
  Both must be resolved against `cwd` before the union, or the same file appears twice.
  Unnormalized comparison shows a spurious 75% divergence between the two sources;
  normalized, they agree to within 2.6% on sessions that have delta records.

Existing fields (`first_msg`, `first_msg_raw`, `last_msg`, `last_msgs_raw`, `cwd`, `size`,
`mtime`) are all retained; the preview and search still use them. The head-50 read for
`cwd` and `first_msg` is unchanged, as is the `if cwd:` rule that skips sessions with no
`cwd` (currently 0 sessions).

**No cache.** At 0.15s for the full corpus there is nothing to cache. This removes the
cache file, its invalidation rule, corruption fallback, pruning policy, concurrency
hazard, and the 205 MB-file problem in one stroke.

### `files_edited` is a minor section

Only **7%** of sessions show any file edit in the tail window (median 2 paths when
non-empty, max 14). `file-history-delta` alone is not sufficient: it tracks the working
directory and is blind to everything outside it. Of 110 recent edit-bearing sessions, 63
have no delta record at all, and only 3 of those 63 edited anything inside their own
`cwd`; the rest edited scratch paths or other repos. `tool_use` is the broader source and
delta adds little once paths are normalized, but the union is cheap and costs nothing.

Render the section only when non-empty and let nothing else depend on it. It is labelled
"Recently edited" because the window is the tail, not the whole session.

### Sanitization

All title-ish and prompt-ish strings pass through one `clean_label()` before display or
storage: strip `<...>` tags (matching `_extract_user_text` at `:139-141`; `last_prompt`
currently bypasses this and real values contain raw XML and embedded JSON), collapse
newlines and control characters to spaces, strip surrounding double quotes (2 of 36
`custom_title` values carry literal quotes), collapse runs of whitespace, and truncate to
a max length. `last_prompt` is already `…`-truncated by Claude Code; treat it as
possibly-truncated text, not full text.

### Row label

**Single line.** Textual's `Tree.process_label` (`_tree.py:846`) does
`text_label.split()[0]` and silently discards everything after a newline, and node height
is fixed at one strip in `_render_line` (`_tree.py:1302`). A two-line row is not
renderable without subclassing the widget, so the design is one line.

```
 2h ago   42KB  Fix flaky auth token refresh test — does the fix cover concurrent callers
```

Title in normal weight, the em-separated `last_prompt` tail in dim, truncated at width.
The `last_prompt` tail is omitted when `last_prompt` is itself the label (precedence 5),
so it never prints twice.

**Byte size stays in the row.** Dropping it would leave the `size` sort mode
(`SORT_MODES` at `:45`, palette entry at `:395`, `group_sessions` at `:260`,
`_next_session_after_removal` at `:1046`) sorting on a quantity nothing on screen shows.
Keeping it costs 7 characters and avoids touching four call sites and the README.

### Label precedence

1. Local name from `session-names.json`
2. `custom_title`
3. Saved summary title, **if** `ai_title` still equals the `ai_title` recorded when the
   summary was generated
4. `ai_title`
5. `last_prompt`
6. `session_id[:12]` (terminal fallback, so an empty session never renders a blank row)

Level 3 is what implements the user's rule. A flat "ai_title always beats summary" list
would make the feature dead on arrival: 74-84% of recent sessions already have an
`ai_title`, so generating a summary would never change the row, which is precisely the
case where the user wants an override (the `ai_title` was bad). Comparing against
`ai_title_at_generation` distinguishes "the user saw this title and chose to override it"
from "the session was resumed and Claude wrote a genuinely new title", and the latter
wins. This is only correct because `ai-title` is regenerated to the end of the session.

### Search

`_search` (`:226`, filtered at `:625`) currently indexes `first_msg + last_msg +
cwd_short + session_id`. It gains `ai_title`, `custom_title`, `last_prompt`, and any
saved summary title and body. Without this, the most prominent text on every row is the
one thing you cannot search for. The separate `session_names` substring match in
`_prepare_tree_data` (`:625`) folds into `_search` so visible text and searched text stay
identical.

### `/rename` handling

Measured: 61 session ids have `/rename` in `history.jsonl`; **0 live sessions have a
`/rename` without an inline `custom-title` record**. The 39 that appeared to lack one are
sessions whose JSONL no longer exists. `custom-title` therefore covers every live rename,
and `load_claude_renames()` (`:85-111`), `HISTORY_FILE` (`:42`), and the history merge in
`load_session_names()` (`:113-124`) are deleted. README updates accordingly.

This also fixes a latent bug: `load_session_names()` merges history-derived names into one
flat dict, and `_do_rename` (`:1088-1093`) calls `save_session_names(self.session_names)`,
which writes the *entire merged dict* to `NAMES_FILE`. The first rename would persist all
61 history-derived names as local names at precedence 1, permanently outranking
`custom_title` and `ai_title`. With the merge gone, `session_names` holds only deliberate
local names.

`RenameDialog` prefill (`action_rename`, `:996`) stays as the local name only (empty when
there is none), so opening the dialog on a Claude-titled session and cancelling cannot
pin that title into `session-names.json`.

### Preview pane

`#preview` is a `Markdown` widget (`:555-558`), so the content must be real markup;
consecutive plain lines would otherwise join into one paragraph. `prepare_markdown()`
(`:308-313`) only rewrites tables and fixes none of this.

```markdown
## Fix flaky auth token refresh test

`~/code/acme-api` · `main` · 42KB

### Where I left off
> does the fix cover concurrent callers or just the single-refresh case

Only the single-refresh path. Concurrent callers still race.

### Recently edited
- `README.md`
- `tests/test_refresh.py`

### Started with
the token refresh test fails about one run in twenty
```

Sections with no data are omitted. File paths render relative to the session `cwd` when
they fall under it, absolute otherwise, capped at 10 with a `+N more` line. The heading is
the resolved label from the precedence list. When a saved summary exists it renders as its
own `### Summary` block above `Where I left off`, dated and marked as generated, whether
or not its title won the row.

The multi-message `TAIL_CHAR_BUDGET` tail (`:183-201`) is replaced by the single
`last_prompt` + `last_assistant` pair under `Where I left off`. `first_msg_raw` is
retained for `Started with`.

## B. On-demand Haiku summary

### Trigger

`c` (for context) plus a command palette entry. Every other reasonable letter is taken in
`BINDINGS` (`:502-522`). Operates on the highlighted session only; there is no bulk or
background path. Re-running on an already-summarized session regenerates and overwrites.

### Invocation

```
claude -p --model haiku --safe-mode --tools '' --no-session-persistence \
  --system-prompt '<summariser prompt>'
```

Reuses the Claude Code CLI the tool already requires, and its OAuth, so no API key and no
new dependency. `--safe-mode` is the load-bearing flag: it disables CLAUDE.md, hooks, MCP,
skills, and plugins. Without it the call takes 6-11s and the user's `CLAUDE.md` leaks into
the output (reproduced: the unisolated run prefixes its answer with the `STARTER_CHARACTER`
from `~/.claude/CLAUDE.md`, intermittently). With it, budget **~4s** (measured 3.8-4.5s)
and clean output. `--bare` is not usable: it refuses OAuth and requires
`ANTHROPIC_API_KEY`, which is not set, and exits 1 with `Not logged in`.

Runs on a `@work(thread=True)` worker, consistent with `_load_sessions_async` (`:558`).
Progress shows in the status bar rather than on the row: `_rebuild_tree` (`:602-610`)
clears and rebuilds the whole tree, and folder expansion and cursor position survive only
through `_pending_view_state`, which is set in exactly one place (`_do_archive`,
`:1068-1071`). Flipping a single row to a pending state through that path would collapse
folders and move the cursor mid-operation. On completion, refresh the preview in place if
the cursor is still on that session, and rebuild the tree only if the row label changed.

### Input construction

User prompts and assistant `text` blocks only. Tool calls and tool results are dropped;
they are most of the bytes and little of the meaning. Head and tail are taken with the
middle elided under a fixed character budget, bounding cost on large sessions (median
26 KB, p90 876 KB, max 205 MB).

### Output contract

The system prompt demands minified JSON, `{"title": "...", "body": "..."}`, no fences.
Verified working against the installed CLI. The response is parsed; on parse failure,
empty title, or non-zero exit, the tool notifies and leaves any existing saved summary
untouched rather than saving garbage. Both fields pass through `clean_label()`.

### Storage

`~/.config/cc-sessions/summaries.json`, keyed by session id:

```json
{"<session-id>": {"title": "...", "body": "...", "generated_at": 1760000000,
                  "session_mtime": 1760000000, "ai_title_at_generation": "..."}}
```

`ai_title_at_generation` drives precedence level 3. `session_mtime` is not an expiry: a
summary never auto-invalidates. It exists so the preview can honestly label a summary
whose session has since changed (`generated <date> · session has changed since`). Both
fields are needed, since `session_mtime` alone cannot distinguish "the user added a turn"
from "Claude wrote a new title".

Writes re-read the file and merge by key before writing, then `os.replace` from a temp
file. Two open TUIs would otherwise silently discard a summary the user paid for. The
existing `_save_prefs` (`:588-593`) already re-reads before writing; this follows it.

`_do_delete` (`:1007-1021`) drops the session's summary alongside `os.remove`.
`_do_archive` (`:1064-1086`) keeps it, since archived sessions can be restored.

## Out of scope

- Bulk or background summarization. On-demand only, by design.
- Special handling for automated sessions. Measured: **0 sessions** have a `last_prompt`
  over 2,000 characters, because Claude Code truncates the stored value. The concern that
  agent-driven sessions would render as walls of instruction text does not survive the
  data.
- Ack-shaped last prompts ("ok", "do it"). Only 7 of 1,391 sessions have a `last_prompt`
  of 15 characters or fewer, and 33 have 40 or fewer, so skip-to-last-substantive-prompt
  logic would add branching for 2% of rows. The title carries the row regardless.
- Compaction summaries as a data source.
- Switching the `size` sort to message count.

## Accepted trade-offs

`ai_title` is generated by Claude Code from the session's own content and can be wrong or
stale on a session that pivoted topics. Both escape hatches are manual: rename (`n`) or
generate a summary (`c`). Rows fall back to `last_prompt`, today's behavior, for the 42%
of older sessions with no title.

The currently-running session is appended to while being read. The existing per-line
`try/except` covers a torn final line, and the next launch re-reads. No locking.

## Error handling

Extraction failures on one session degrade to whatever fields parsed and never abort the
scan, matching the existing `try/except` posture in `load_sessions()`. A failed or
timed-out `claude -p` call notifies and preserves any existing summary. The summariser
subprocess gets an explicit timeout.

## Testing

The repo has no tests, no framework, and no CI, and the module has no `.py` extension.
Renaming it would touch `install.sh` and both shell wrappers, which is churn this change
should not carry. Instead: one `tests/test_extract.py` loading the module via
`importlib.util.spec_from_file_location`, plus pytest as a dev-only dependency, covering
the two things that will actually be wrong:

1. **Label precedence**, table-driven across all six levels, including the
   `ai_title_at_generation` comparison in both directions.
2. **Extraction and `clean_label()`** over one fixture JSONL containing every record type,
   a malformed line, a `custom_title` with literal surrounding quotes, and a `last_prompt`
   containing XML tags.

Broken extraction is obvious the moment the TUI opens; precedence is not. Beyond these,
verification is running the TUI against the real corpus.
