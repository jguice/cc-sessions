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

**These records are always near the end of the file.** `ai-title` is rewritten repeatedly
as a session progresses, median gap 22 lines. Measured across all 1,391 sessions, the
worst-case distance from EOF back to the earliest of the three is **31,365 bytes**, or 24%
of the window, across **zero misses in 1,391 sessions**.

The bound is empirical, not structural. 100 files contain single JSONL lines larger than
128 KB (largest 16.4 MB), and because the seek lands mid-line the usable window shrinks by
the torn prefix: one file has a 112,927-byte prefix leaving 18,145 usable against a record
at 17,956, a true margin of 189 bytes. Nothing misses today, but do not treat "4x headroom"
as the safety story.

A **128 KB tail read therefore recovers all three identically to a full-file scan, with
zero misses and zero mismatches**, in **0.26s for the whole corpus** (0.20s at the old
30-line cap). `_read_tail_lines`
already reads a 128 KB tail (`cc-sessions-tui:231-246`), so extraction needs no cache and
no full-file scan.

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
| **All** | **58%** | **99.3%** |

The gap is feature age and improves on its own. Treat these as shape, not exact digits:
resuming a session rewrites its mtime and reshuffles the buckets, so an independent
recount lands within a few points either way. `ai_title` length is median 45 chars, max
71, so it fits a row. The `last-prompt` figure counts records that actually carry the
`lastPrompt` field, which is what extraction requires; 99.86% have a record at all.
Compaction summaries (`isCompactSummary`) exist in 24 files and are not used.

Corpus composition matters for reading any of these numbers: **786 of 1,391 sessions are
under 10 lines**, single-turn automated runs. They dominate any whole-corpus median.
Segmenting by session length is what exposes the regeneration behavior above: median
relative position of the last `ai-title` is 0.500 for sessions under 20 lines but **0.995
for sessions over 300 lines**.

## Scope

- **A.** Read what Claude Code already stores; retitle rows, restructure the preview.
- **B.** On-demand Haiku summary for one selected session, saved to disk.

## A. Extraction and display

### Extraction

Extend the existing tail read in `load_sessions()` (`:151`) rather than adding a scan.

`_read_tail_lines` keeps its 128 KB window, but the **call site at `:185` passes
`max_lines=30` explicitly**, so changing the default at `:231` does nothing. Drop the
parameter and the `lines[-max_lines:]` slice at `:244` entirely; the window is the only
bound that matters. Cost measured across all 1,391 sessions: **0.26s parsing the full
window versus 0.20s for today's 30-line cap**. A 128 KB window holds a median of 7 lines,
p90 63, p99 109, max 138.

With the slice gone, `lines[0]` is a **partial line** for any file over 128 KB, because
the seek lands mid-line. The existing per-line `try/except` at `:187-190` already discards
it. This is expected, not an extraction error; do not add a guard.

| Field | Source (all within the 128 KB tail) |
|---|---|
| `ai_title` | last `ai-title` record |
| `custom_title` | last `custom-title` record |
| `last_prompt` | last `last-prompt` record **that has a `lastPrompt` field** |
| `last_assistant` | last non-`<synthetic>` assistant `text` block, **only if it follows the last user message in file order** |
| `files_edited` | union of `tool_use` Edit/Write/NotebookEdit `file_path` and `file-history-delta.trackingPath`, **normalized to absolute against `cwd` first** |

Four extraction details are not optional:

- **87 of 10,693 `last-prompt` records (0.8%) carry only `{type, leafUuid, sessionId}`**
  with no `lastPrompt` field. Take the last record that actually has the field.
- **`message.model` is the literal string `<synthetic>` on the last assistant record in
  10.4% of sessions** (37% of all assistant records), emitted for interrupts and errors.
  `model` is displayed nowhere in this design, but `last_assistant` must skip synthetic
  records or "where I left off" becomes an interrupt notice one time in ten.
- **`last_assistant` must follow the last user message in file order.** When a session
  ended mid-tool-use or was interrupted, the last assistant *text* predates the final
  prompt, and pairing them renders an exchange that never happened. Both indices are
  already in the parsed window, so this is an index comparison.
- **`file-history-delta.trackingPath` is cwd-relative when the file sits under the session
  `cwd` and absolute otherwise**, while `tool_use.file_path` is always absolute. Resolve
  both against `cwd` before the union or the same file appears twice. Unnormalized
  comparison shows a spurious 75% divergence; normalized, the sources agree to within 2.6%
  on sessions that have delta records.

### The 128 KB guarantee does not extend to every field

The zero-miss result was measured for the three title/prompt records, which Claude Code
writes near EOF by construction. `last_assistant` has no such property and was measured
separately across all 1,391 sessions:

| Outcome | Share |
|---|---|
| Assistant text present and follows the last user message | **87.3%** |
| No non-synthetic assistant text in the tail window | **11.4%** |
| Assistant text present but predates the last user message | **1.2%** |

**Which user records count is load-bearing and must be stated.** The figures above hold
only when "last user message" excludes `isMeta` records and tool_result carriers. Reusing
`_extract_user_text` (`:139-141`) as-is does not filter `isMeta`, and lands at 74.9% /
11.4% / **13.6%**; an 11x worse degradation rate. The 195 predates-cases are 172 `isMeta`
hook injections, 7 tool_result carriers, 11 `[Request interrupted by user]` blocks, and 5
`<local-command-stdout>` strings from `/compact`.

Under the stated filter, `Where I left off` shows prompt plus reply 87% of the time and
**degrades to prompt-only for the other 13%**, which is acceptable because `last_prompt`
alone is a real answer at 99.3% coverage.

**`git_branch` is deliberately not extracted.** It rides on ordinary conversation records
rather than being appended at EOF, so its last occurrence sits up to **125,982 bytes from
EOF, 96.1% of the window**, versus 24% for the title records. It was the only field in the
design with no headroom, and it is decorative. Dropping it makes the tail bound depend
solely on records Claude Code appends at the end of the file.

### Fields retained, changed, and retired

The backwards walk at `:183-201` is **kept** (it parses lines already in the window at
near-zero cost) but its output narrows:

- `last_msg`: **kept**, feeds `_search` and the precedence-6 row fallback. It uses the
  **same user-record predicate as `last_assistant`** (excluding `isMeta` records and
  tool_result carriers). Otherwise a level-6 row can be labeled with a hook injection or
  `[Request interrupted by user]`, which carries no tags and so survives the `<...>` strip.

**The filter goes inside `_extract_user_text` (`:139-153`), not into a separate predicate.**
Every consumer wants the same definition of "a message the user actually typed", and the
function is the one place in the file that decides it. This is a deliberate behavior change
with a measured blast radius: `last_msg` changes on **222 of 1,389 sessions (16%)** and
`first_msg` on 17. That is intended, not a regression. Filtering only at the ordering
comparison would leave level 6 rescuing a session from a hex id by labeling it with the
exact hook injection the filter exists to exclude.
- `last_msgs_raw`: **retired.** Its only consumer is `_update_preview` (`:731-745`), and
  `Where I left off` supersedes it. `TAIL_CHAR_BUDGET` goes with it.
- `first_msg`, `first_msg_raw`, `cwd`, `size`, `mtime`: unchanged.

The head-50 read for `cwd` and `first_msg` is unchanged, as is the `if cwd:` rule at `:208`
that skips sessions with no `cwd` (currently 0 sessions).

**No cache.** At 0.26s for the full corpus there is nothing to cache. This removes the
cache file, its invalidation rule, corruption fallback, pruning policy, concurrency
hazard, and the 205 MB-file problem in one stroke.

### `files_edited` is a minor section

Only **7%** of sessions show any file edit in the tail window (median 2 paths when
non-empty, max 7). `file-history-delta` alone is insufficient: it tracks the working
directory and is blind to everything outside it. Of 110 recent edit-bearing sessions, 63
have no delta record, and only 3 of those 63 edited anything inside their own `cwd`. The
`tool_use` source is broader; delta adds little once normalized, but the union is free.

Render the section only when non-empty and let nothing else depend on it. It is labelled
"Recently edited" because the window is the tail, not the whole session.

### Two sanitizers, not one

A single `clean_label()` applied to everything would mangle the summary body: collapsing
newlines flattens prose, a title-sized cap decapitates it, and stripping `<...>` eats
`<Component>`, generics, and shell redirects in text about code.

- **`clean_label(s, max_len=200)`**: for row-label and heading sources (`ai_title`,
  `custom_title`, `last_prompt`, `last_msg`, summary title). Strips `<...>` tags (matching
  `_extract_user_text` at `:139-141`; `last_prompt` currently bypasses this and real values
  contain raw XML and embedded JSON), collapses newlines and control characters to spaces,
  strips surrounding double quotes (2 of 36 `custom_title` values carry literal quotes),
  collapses whitespace runs, truncates to `max_len`.
- **`clean_body(s, max_len=2000)`**: for the summary body and `last_assistant`. Strips
  control characters, preserves newlines, demotes leading `#` runs to bold so injected
  model text cannot open a heading that sits as a peer of the preview's own sections,
  truncates to `max_len`, then **balances code fences**: if the result contains an odd
  number of ``` markers, append a closing one. Without this a cut landing inside a fence
  leaves it open and swallows every section below it into a code block.

**`max_len` is per call site, not per field.** `last_prompt` is capped at 200 for the row
and 2,000 for the preview blockquote, which is the pane's headline content and should not
lose text to a row-sized cap. Max observed `last_prompt` is 201 characters, so this is
cheap insurance rather than a live problem.

`first_msg_raw` and `last_assistant` pass through `clean_body()` for the heading-injection
reason, then through `prepare_markdown()` (`:308-313`), in that order. `prepare_markdown`
emits fenced blocks, so running it before truncation would reintroduce the unbalanced-fence
bug. Keeping it means tables still render in `Started with` and now also in the assistant
reply, the likelier place to contain one; `render_table()` (`:276-306`) stays.

### Row label

**Single line.** Textual's `Tree.process_label` (`_tree.py:846`) does
`text_label.split()[0]` at `:861` and silently discards everything after a newline, and node height
is fixed at one strip in `_render_line` (`_tree.py:1313`). A two-line row is not renderable
without subclassing the widget.

```
 2h ago   42KB  Fix flaky auth token refresh test · does the fix cover concurrent callers
```

The Nerd Font icons (`ICON_CLOCK`, `ICON_SIZE`) stay exactly as they are at `:670-671`.
Title in normal weight, the `·`-separated `last_prompt` tail in dim (`label.append(...,
style="dim")` is already in use at `:671`). The tail is omitted when `last_prompt` is
itself the label, so it never prints twice.

**Labels are not truncated.** Textual does not ellipsize: `Tree._build` sets
`virtual_size` from the widest label (`_tree.py:1279-1291`) and `_render_line` pads and
crops (`_tree.py:1433-1437`), so long labels produce a horizontal scrollbar. Today's rows
already do this, appending the full untruncated `last_msg` at `:675`. App-side truncation
would need a width source that `_prepare_tree_data` (on a worker thread, no widget access)
does not have, plus an `on_resize` handler that does not exist anywhere in the file. The
`clean_label()` cap bounds the damage; the scrollbar behavior is unchanged from today.

**The `[name]` bracket prefix is removed.** At `:673-674` a local name renders as
`[name] ` before the message text. Under precedence level 1 the name *is* the label, so
the bracket form disappears.

**Byte size stays in the row.** Dropping it would leave the `size` sort mode (`:45`,
palette at `:392`, `group_sessions` at `:260`, `_next_session_after_removal` at `:1031`)
sorting on a quantity nothing on screen shows. Keeping it costs 7 characters.

### Label precedence

1. Local name from `session-names.json`
2. `custom_title`
3. Saved summary title, **if** `ai_title` is unchanged since the summary was generated
4. `ai_title`
5. `last_prompt`
6. `last_msg` (the tail-derived last user message)
7. `session_id[:12]` (terminal fallback, so an empty session never renders a blank row)

Level 6 exists because `last_prompt` carries a usable `lastPrompt` field on 99.3% of
sessions, so roughly ten sessions in the corpus would otherwise render as a hex id while a
perfectly good last user message sits already extracted.

Level 3 implements the user's rule. A flat "ai_title always beats summary" list would make
the feature dead on arrival: 74-84% of recent sessions already have an `ai_title`, so
generating a summary would never change the row, which is exactly the case where the user
wants an override. Comparing against `ai_title_at_generation` distinguishes "the user saw
this title and chose to override it" from "the session was resumed and Claude wrote a
genuinely new title", and the latter wins. This is only correct because `ai-title`
regenerates to the end of the session.

**The equality test is defined as:** both sides normalized through `clean_label()`, with
absent/empty/`None` all coerced to `""` before comparison. Without this, a title containing
a quote or a tag compares unequal forever and the summary silently loses the row with no
visible cause. A `summaries.json` entry missing the field reads as `""`, which correctly
compares equal to "no `ai_title` now".

**Named consequence:** for the 42% of sessions with no `ai_title`, generating a summary
stores `""`, the summary wins the row, and then *resuming that session writes a real
`ai_title` which takes the row back*. This is the highest-frequency transition in the
design and it follows from the user's stated rule, but it means a paid-for label can be
replaced by a machine one on next resume.

### Search

`_search` (`:226`, filtered at `:625`) currently indexes `first_msg + last_msg + cwd_short
+ session_id`. It gains `ai_title`, `custom_title`, and `last_prompt`, all static for the
lifetime of a load, so they are safe to prebuild.

**Local names and summaries stay in the live filter expression** alongside the existing
`session_names` lookup at `:625-627`. Both mutate at runtime (`_do_rename` at `:1088`, and
the summary-save path), and a prebuilt string would go stale the instant you rename or
summarize, failing silently: you rename a session, search the new name, get nothing.
Keeping them live costs one substring check per row and needs no invalidation.

### `/rename` handling

Measured: 61 session ids have `/rename` in `history.jsonl`; 22 point at sessions still on
disk, and **all 22 carry a `custom-title` record inside the 128 KB tail**. Zero live
sessions need the history path. `load_claude_renames()` (`:85-111`), `HISTORY_FILE`
(`:43`), and the merge in `load_session_names()` (`:113-124`) are deleted. Nothing in
`install.sh`, `cc-sessions.sh`, or `cc-sessions.fish` references them.

`README.md:92` currently reads: *"Session names set via Claude's `/rename` command are
auto-detected from `~/.claude/history.jsonl`. Local names in `session-names.json` take
priority when both exist."* It is replaced by: *"Session names set via Claude's `/rename`
command are read from the session file itself. Local names in `session-names.json` take
priority when both exist."*

This also fixes a latent bug: `load_session_names()` merges history-derived names into one
flat dict, and `_do_rename` (`:1088-1093`) calls `save_session_names(self.session_names)`,
which writes the *entire merged dict* to `NAMES_FILE`. The first rename would persist all
61 history names as local names at precedence 1, permanently outranking `custom_title` and
`ai_title`. `session-names.json` does not exist on this machine, so the bug has never
fired and **no migration or cleanup code is needed**.

Two more call sites depend on the merge and must move to the resolved precedence label:
`action_delete` (`:961`) and `action_archive` (`:972`) both do
`self.session_names.get(sid, sid[:12])`, so a `/rename`d session would prompt *"Delete
session 'a1b2c3d4e5f6'?"* despite its row showing a proper title. That is 22 sessions here.

`RenameDialog` prefill (`action_rename`, `:996`) stays as the local name only (empty when
there is none), so opening the dialog on a Claude-titled session and cancelling cannot pin
that title into `session-names.json`.

### Preview pane

`#preview` is a `Markdown` widget (`:545`), so content must be real markup;
consecutive plain lines would otherwise join into one paragraph. `prepare_markdown()`
(`:308-313`) only rewrites tables and fixes none of this.

```markdown
## Fix flaky auth token refresh test

`~/code/acme-api` · 42KB

### Summary
*Generated 2026-08-11 · "Auth token refresh race condition"*

Reproduced the flake: refresh() returns before the renewal settles...

### Where I left off
> does the fix cover concurrent callers or just the single-refresh case

Only the single-refresh path. Concurrent callers still race.

### Recently edited
- `README.md`
- `tests/test_refresh.py`

### Started with
the token refresh test fails about one run in twenty
```

The heading is the resolved precedence label. Sections with no data are omitted, and the
` · ` metadata line joins conditionally. File paths render relative to `cwd` when they fall
under it, absolute otherwise, capped at 10 with a `+N more` line.

The `Summary` block renders whenever a saved summary exists, **including its own title**,
so a user whose summary lost the row to a newer `ai_title` can still see that it exists and
why. When `session_mtime` is older than the session's current `mtime` the header gains
`· session has changed since`.

### Accepted trade-off on stale summary rows

A stale summary title keeps precedence 3 in the row with no marker; the staleness note
appears only in the preview, after selection. Marking it in the row would mean appending a
dim character to the label whenever `session_mtime < mtime` and the summary won. This is
deliberately not done: `ai_title` regenerates every ~20 lines, so on any resume long enough
to matter the title changes and level 4 takes the row back anyway.

## B. On-demand Haiku summary

### Trigger

`c` (for context) plus a command palette entry. Every other reasonable letter is taken in
`BINDINGS` (`:502-522`). Operates on the highlighted session only; no bulk or background
path. Re-running regenerates and overwrites.

**Pressing `c` twice on the same session is guarded** by tracking in-flight session ids and
ignoring the repeat. Otherwise two subprocesses run, both merged writes land, last one
wins, and both were paid for.

### Invocation

```
claude -p --model haiku --safe-mode --tools '' --no-session-persistence \
  --system-prompt '<summariser prompt>'
```

Reuses the Claude Code CLI the tool already requires, and its OAuth, so no API key and no
new dependency. `--safe-mode` is the load-bearing flag: it disables CLAUDE.md, hooks, MCP,
skills, and plugins. Without it the call takes 6-11s and the user's `CLAUDE.md` leaks into
the output (reproduced: the unisolated run prefixes its answer with the `STARTER_CHARACTER`
from `~/.claude/CLAUDE.md`, intermittently). With it, output is clean. Wall time scales with how much
conversation text the session yields: a trivial prompt returns in ~4s, while a real
session with a full input budget measured **17.5s and 24.0s**. The subprocess timeout is
therefore **90s**, not 30s. `--bare` is not usable: it
refuses OAuth, requires `ANTHROPIC_API_KEY` which is not set, and exits 1 with
`Not logged in`.

Runs on a `@work(thread=True)` worker, consistent with `_load_sessions_async` (`:558`).
Progress shows in the status bar, not on the row: `_rebuild_tree` (`:602-610`) clears and
rebuilds the whole tree, so a per-row pending state would collapse folders mid-operation.

**On completion**, set `self._pending_view_state = (self._snapshot_expanded_cwds(),
session_id)` *before* rebuilding, reusing the existing mechanism (`:1023`, consumed at
`:679-695`). The row label changes precisely when the summary wins precedence 3, which is
the happy path, so without this the reward for generating a summary is every folder
collapsing and the cursor jumping to the top. `_select_leaf_after_refresh` (`:696-701`) already calls `_update_preview`
when it restores the cursor, so no separate preview refresh is needed on that branch.
**Notify with the resulting title** so a regeneration
that produced the same text is visibly distinguishable from a no-op.

### Input construction

User prompts and assistant `text` blocks only; tool calls and results are dropped, being
most of the bytes and little of the meaning. Head is a **bounded read from the start**
(256 KB) and tail a **bounded seek from EOF** (512 KB), so the middle is never read. A
line-by-line filter across the 205 MB session would satisfy "head and tail with the middle
elided" while stalling the worker for minutes.

**Both chunk boundaries land mid-line and both partial lines must be dropped**: the tail's
first line and the head's last. Extracted text is then capped at 60 KB.

These budgets were tuned against measurement, not guessed. At 40 KB / 60 KB a 3.5 MB
session yielded only 1,442 characters of conversation, because tool payloads dominate the
bytes, and the resulting summary was visibly shallow and partly wrong. At 256 KB / 512 KB
the same session yields 4,221 characters and an accurate summary. The reads themselves are
free (0.00s); latency comes from the model call.

### Output contract

The system prompt demands minified JSON, `{"title": "...", "body": "..."}`, no fences.
Verified working against the installed CLI. On parse failure, empty title, non-zero exit,
or timeout, the tool notifies and leaves any existing saved summary untouched rather than
saving garbage. `title` passes through `clean_label()`, `body` through `clean_body()`.

### Storage

`~/.config/cc-sessions/summaries.json`, keyed by session id:

```json
{"<session-id>": {"title": "...", "body": "...", "generated_at": 1760000000,
                  "session_mtime": 1760000000, "ai_title_at_generation": "..."}}
```

`ai_title_at_generation` stores the **`clean_label()`ed** value, matching the comparison.
`session_mtime` is not an expiry: a summary never auto-invalidates. It exists so the
preview can honestly label a summary whose session has since changed. Both fields are
needed, since `session_mtime` alone cannot distinguish "the user added a turn" from
"Claude wrote a new title".

Loaded in `_load_sessions_async` (`:559-562`) alongside `load_sessions()` and passed into
`_finish_loading` (`:564-573`), which stores it as `self.summaries`. **`self.summaries` and the in-flight session-id set are
both initialized in `__init__` (`:524-534`)**, matching `self.session_names` today:
`watch_theme` (`:575-582`) calls `_rebuild_tree()` and can fire from the command palette
before `_finish_loading` runs, which would otherwise hit `_prepare_tree_data` with the
attribute undefined. `_prepare_tree_data`
(`:618-642`) reads it when resolving the label, so its per-item dict gains a `label` key
rather than the current `name` key.

Writes re-read the file and merge by key before writing, then `os.replace` from a temp
file. Two open TUIs would otherwise silently discard a summary the user paid for. The
existing `_save_prefs` (`:593`) already re-reads before writing; this follows it.

`_do_delete` (`:1007-1021`) drops the session's `summaries.json` **and**
`session-names.json` entries alongside `os.remove`. `_do_archive` (`:1064-1086`) keeps
both, since archived sessions can be restored.

## Out of scope

- Bulk or background summarization. On-demand only, by design.
- Special handling for automated sessions. Measured: **max observed `last_prompt` is 201
  characters**, because Claude Code truncates the stored value hard.
- Ack-shaped last prompts ("ok", "do it"). Only 7 of 1,391 sessions have a `last_prompt`
  of 15 characters or fewer, and 33 have 40 or fewer.
- Compaction summaries as a data source.
- Switching the `size` sort to message count. `turn_duration` records exist in only 5.4%
  of sessions (15 of the newest 100), so `message_count` would be blank on most rows.
- Marking stale summary rows in the list (see the trade-off above).

## Accepted trade-offs

`ai_title` is generated by Claude Code from the session's own content and can be wrong on
a session that pivoted topics. Both escape hatches are manual: rename (`n`) or generate a
summary (`c`). Rows fall back to `last_prompt` for the 42% of older sessions with no title.

The currently-running session is appended to while being read. The existing per-line
`try/except` covers a torn final line, and the next launch re-reads. No locking.

The 128 KB window bound is empirical (see Key finding), and no re-read guard is added for
it; that would be defensive code for a case that does not occur in 1,391 sessions. The
consequence of a future miss is bounded and silent: nothing crashes, the affected field is
simply absent, and the row falls to the next precedence level.

## Error handling

Extraction failures on one session degrade to whatever fields parsed and never abort the
scan, matching the existing `try/except` posture in `load_sessions()`. A failed or
timed-out `claude -p` call notifies and preserves any existing summary.

## Testing

The repo has no tests, no framework, and no CI, and the module has no `.py` extension.
Renaming it would touch `install.sh` and both shell wrappers, which is churn this change
should not carry. Instead: one `tests/test_extract.py` loading the module via
`importlib.util.spec_from_file_location`, plus a `requirements-dev.txt` declaring pytest
and a line in the README's Contributing section giving the explicit command
(`~/.local/share/cc-sessions-venv/bin/pip install -r requirements-dev.txt`), since
`install.sh:17` hardcodes `pip install -q textual` and there is no runtime
`requirements.txt`. Loading the module executes its top-level
`textual` and `rich` imports, so tests run inside the existing venv.

Two test groups, covering the two things that will actually be wrong:

1. **Label precedence**, table-driven across all seven levels, including the
   `ai_title_at_generation` comparison in three directions: unchanged (summary wins),
   changed (ai_title wins), and absent-on-both-sides coerced to `""` (summary wins).
2. **Extraction, `clean_label()`, and `clean_body()`** over one fixture JSONL containing
   every record type, a malformed line, a partial first line, a `last-prompt` record
   missing its `lastPrompt` field, a `<synthetic>` terminal assistant record, an assistant
   text block preceding the last user message, an `isMeta` user record after the last real
   one (the case that separates 87.3% from 74.9%), a `custom_title` with literal surrounding
   quotes, and a `last_prompt` containing XML tags.

Broken extraction is obvious the moment the TUI opens; precedence is not. Beyond these,
verification is running the TUI against the real corpus.

## As built

Implemented in 55d088b..9533d76. What changed from the design above, and why:

**`resolve_label` returns `(label, source)`, not a bare string.** Every label rendered
identically, so there was no way to tell Claude Code's own title from a rename, a generated
summary, or raw transcript text. `LABEL_SOURCES` maps each of the seven levels to a glyph
and a description.

**Rows carry a source glyph; untitled rows render dimmed italic.** The glyph set is
single-width Font Awesome so columns stay aligned: pencil for a name you set, star for a
summary you generated, magic wand for Claude Code's title, empty circle for no title yet.
`U+F544` was tried first and renders as a fallback character in the user's font; the
newer Material Design range has spotty coverage, so stay in `U+F0xx-F2xx`. Emoji render
reliably but are double-width and ragged the column.

**The preview names the source with the glyph alone, not prose.** An earlier
"**Showing:** ..." line read as a floating fragment rather than an annotation of the
heading. The glyph now sits on the heading itself. `?` opens `LegendScreen`, which lists
one row per glyph (local/custom share one, as do prompt/message/id) plus the precedence
order.

**The summary block omits its own title when that title is already the heading**, which is
the common case, and shows Claude's own title on a separate line only when something else
won the row. Those are different facts, not a restatement.

**`Started with` precedes `Where I left off`** so the pane reads in time order.

**A mouse click previews; a second click on the same row resumes.** Selecting a row
resumed it immediately, which made the list unbrowsable by mouse. `Enter` is unchanged,
since the row is already highlighted when you press it. Tracked with `_mouse_input`
(set in `on_mouse_down`, cleared in `on_key`) and `_armed_id` (cleared on highlight change).

**Default sort is recency**, not folder name.

**Summarizing shows an animated spinner and elapsed seconds** on both the status bar and
the row itself, repainted via `node.set_label()` on a 0.1s interval. A status-bar string
alone was missed entirely during a 5-25s call. The row is repainted in place rather than
through `_rebuild_tree`, which would collapse folders mid-run.

**The single tail read serves everything.** `_parse_tail` returns `last_msg` alongside the
titles, so `load_sessions` reads the window once rather than twice. Full load of 1,390
sessions measures 0.80s.

**`git_branch` was dropped** before implementation; see the Key finding section.
