"""Tests for cc-sessions extraction, sanitizing, and label precedence.

The TUI has no .py extension, so it loads via SourceFileLoader. It imports textual and
rich at module scope, so these run inside the venv:

    ~/.local/share/cc-sessions-venv/bin/python -m pytest tests/
"""

import importlib.machinery
import importlib.util
import json
import os

import pytest

MODULE_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "cc-sessions-tui")


def _load():
    loader = importlib.machinery.SourceFileLoader("cc_sessions_tui", MODULE_PATH)
    spec = importlib.util.spec_from_loader("cc_sessions_tui", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


cct = _load()


# ---------------------------------------------------------------------------
# Label precedence
# ---------------------------------------------------------------------------

SID = "abcdef123456789"


def _session(**kw):
    base = {
        "session_id": SID,
        "custom_title": "",
        "ai_title": "",
        "last_prompt": "",
        "last_msg": "",
    }
    base.update(kw)
    return base


@pytest.mark.parametrize("label,session,names,summaries,expected", [
    ("1 local name beats everything",
     _session(custom_title="C", ai_title="A"), {SID: "LOCAL"}, {}, ("LOCAL", "local")),
    ("2 custom_title beats ai_title",
     _session(custom_title="C", ai_title="A"), {}, {}, ("C", "custom")),
    ("3 summary wins while ai_title unchanged",
     _session(ai_title="A"), {},
     {SID: {"title": "S", "ai_title_at_generation": "A"}}, ("S", "summary")),
    ("4 a genuinely new ai_title supersedes the summary",
     _session(ai_title="NEW"), {},
     {SID: {"title": "S", "ai_title_at_generation": "A"}}, ("NEW", "ai")),
    ("3 absent-on-both-sides coerces to empty and the summary wins",
     _session(), {}, {SID: {"title": "S", "ai_title_at_generation": ""}}, ("S", "summary")),
    ("3 a missing ai_title_at_generation key reads as empty",
     _session(), {}, {SID: {"title": "S"}}, ("S", "summary")),
    ("4 a session with no title at generation that later gains one loses the row",
     _session(ai_title="A"), {}, {SID: {"title": "S"}}, ("A", "ai")),
    ("4 ai_title beats last_prompt",
     _session(ai_title="A", last_prompt="P"), {}, {}, ("A", "ai")),
    ("5 last_prompt beats last_msg",
     _session(last_prompt="P", last_msg="M"), {}, {}, ("P", "prompt")),
    ("6 last_msg rescues a session with no prompt record",
     _session(last_msg="M"), {}, {}, ("M", "message")),
    ("7 terminal fallback is the session id prefix",
     _session(), {}, {}, (SID[:12], "id")),
])
def test_label_precedence(label, session, names, summaries, expected):
    assert cct.resolve_label(session, names, summaries) == expected


def test_every_source_key_is_describable():
    """Every precedence level must be nameable in the preview, or the user cannot tell
    Claude Code's own title apart from raw transcript text."""
    for key in ("local", "custom", "summary", "ai", "prompt", "message", "id"):
        assert key in cct.LABEL_SOURCES
        _, description = cct.LABEL_SOURCES[key]
        assert description


def test_equality_test_normalizes_both_sides():
    """A stored raw title must still match the cleaned extracted one."""
    session = _session(ai_title=cct.clean_label('"Quoted"'))
    summaries = {SID: {"title": "S", "ai_title_at_generation": '"Quoted"'}}
    assert cct.resolve_label(session, {}, summaries) == ("S", "summary")


# ---------------------------------------------------------------------------
# Sanitizers
# ---------------------------------------------------------------------------

def test_clean_label_strips_tags_quotes_and_newlines():
    assert cct.clean_label("<tag>hi</tag>  there") == "hi there"
    assert cct.clean_label('"Quoted Title"') == "Quoted Title"
    assert cct.clean_label("a\nb\tc") == "a b c"


def test_clean_label_respects_per_call_site_max_len():
    assert len(cct.clean_label("x" * 500, 200)) == 200
    assert len(cct.clean_label("x" * 500, 2000)) == 500


def test_clean_body_balances_a_truncated_code_fence():
    out = cct.clean_body("text ```code here", max_len=14)
    assert out.count("```") % 2 == 0, "an unclosed fence swallows every section below it"


def test_clean_body_demotes_headings_and_keeps_newlines():
    assert cct.clean_body("## Heading\nbody") == "**Heading**\nbody"


def test_clean_body_leaves_balanced_fences_alone():
    assert cct.clean_body("a\n```\ncode\n```\nb").count("```") == 2


# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

CWD = "/tmp/proj"

FIXTURE = [
    {"type": "user", "cwd": CWD, "message": {"content": "first typed message"}},
    {"type": "assistant", "message": {"model": "claude-x", "content": [
        {"type": "text", "text": "an earlier reply"}]}},
    "{ this line is malformed",
    {"type": "assistant", "message": {"model": "claude-x", "content": [
        {"type": "tool_use", "name": "Edit", "input": {"file_path": CWD + "/a.py"}}]}},
    {"type": "file-history-delta", "trackingPath": "b.py"},
    {"type": "user", "message": {"content": [{"type": "tool_result", "content": "ignored"}]}},
    {"type": "user", "isMeta": True, "message": {"content": "Stop hook feedback: ignored"}},
    {"type": "user", "message": {"content": "the real last message"}},
    {"type": "assistant", "message": {"model": "claude-x", "content": [
        {"type": "text", "text": "the final reply"}]}},
    {"type": "assistant", "message": {"model": "<synthetic>", "content": [
        {"type": "text", "text": "[Request interrupted by user]"}]}},
    {"type": "ai-title", "aiTitle": "A generated title"},
    {"type": "custom-title", "customTitle": '"Renamed"'},
    {"type": "last-prompt", "leafUuid": "x"},
    {"type": "last-prompt", "lastPrompt": "do the <thing> please"},
]


@pytest.fixture
def session_file(tmp_path):
    path = tmp_path / "session.jsonl"
    with open(path, "w") as f:
        for entry in FIXTURE:
            f.write(entry if isinstance(entry, str) else json.dumps(entry))
            f.write("\n")
    return str(path)


def test_titles_and_prompt_come_from_the_last_valid_record(session_file):
    out = cct._parse_tail(session_file, CWD)
    assert out["ai_title"] == "A generated title"
    assert out["custom_title"] == "Renamed", "surrounding quotes should be stripped"
    assert out["last_prompt"] == "do the <thing> please", (
        "the last-prompt record without a lastPrompt field must be skipped"
    )


def test_last_msg_skips_isMeta_and_tool_results(session_file):
    out = cct._parse_tail(session_file, CWD)
    assert out["last_msg"] == "the real last message"


def test_last_assistant_skips_synthetic_records(session_file):
    out = cct._parse_tail(session_file, CWD)
    assert out["last_assistant"] == "the final reply"


def test_last_assistant_omitted_when_it_predates_the_last_prompt(tmp_path):
    path = tmp_path / "s.jsonl"
    with open(path, "w") as f:
        f.write(json.dumps({"type": "assistant", "message": {
            "model": "claude-x", "content": [{"type": "text", "text": "stale reply"}]}}) + "\n")
        f.write(json.dumps({"type": "user", "message": {"content": "asked after"}}) + "\n")
    out = cct._parse_tail(str(path), CWD)
    assert out["last_assistant"] == "", (
        "pairing a reply with a later prompt renders an exchange that never happened"
    )


def test_files_edited_unions_both_sources_and_normalizes_paths(session_file):
    out = cct._parse_tail(session_file, CWD)
    assert sorted(out["files_edited"]) == [CWD + "/a.py", CWD + "/b.py"], (
        "trackingPath is cwd-relative, file_path is absolute; both must normalize"
    )


def test_malformed_lines_do_not_abort_extraction(session_file):
    assert cct._parse_tail(session_file, CWD)["ai_title"] == "A generated title"


def test_extract_user_text_rejects_meta_and_tool_results():
    assert cct._extract_user_text(
        {"type": "user", "isMeta": True, "message": {"content": "hook"}}) is None
    assert cct._extract_user_text(
        {"type": "user", "message": {"content": [{"type": "tool_result", "content": "x"}]}}) is None
    assert cct._extract_user_text(
        {"type": "user", "message": {"content": "typed"}})[0] == "typed"
