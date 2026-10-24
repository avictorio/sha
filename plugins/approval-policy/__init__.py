r"""approval-policy: a pre_tool_call policy plugin for Hermes Agent (template).

Skeleton built from the documented hook contract — verify against your installed Hermes version.

Contract used (docs/verification-notes.md F9, notes #9):
  - register(ctx) calls ctx.register_hook("pre_tool_call", fn).
  - fn receives keyword arguments tool_name, args, task_id, plus **kwargs, and fires
    before every tool call (built-in or plugin), separately for each parallel call.
  - Return {"action": "block", "message": "<non-empty>"}  -> the call never runs.
    Return {"action": "approve", "message": "...", "rule_key": "..."} -> Hermes asks
    you through its human-approval prompt (on Telegram: reply yes / no).
    Return None -> no decision. Precedence: block > approve > nothing.
  - Denial, approval timeout, a callback that raises, or a callback slower than
    plugins.hook_callback_timeout (default 30 s) all fail CLOSED (the tool is blocked).
    gate() below also turns its own internal errors into an explicit block.

Install: installer/steps/08-plugins.ps1 -Profile default|local (PLAN.md P2.1). It copies this folder to
  cloud profile:  %LOCALAPPDATA%\hermes\plugins\approval-policy\
  local profile:  %LOCALAPPDATA%\hermes\profiles\local\plugins\approval-policy\
runs `hermes [-p local] plugins enable approval-policy`, and restarts that profile's gateway with
scripts/restart-gateway.ps1 (never `hermes gateway restart`; docs/LESSONS.md, Hermes).

Self-test: ask the bot to run  echo approval-selftest  -> you should get an approval prompt.

Confirmed by a day of LOG_ALL_TOOL_CALLS (P2.1 step 3, 2026-10-24): terminal (command, timeout,
workdir), execute_code (code), browser_exec (code). Names NOT confirmed yet:
  - make_call's argument names (Spike S12)
  - browser_vault's argument names other than `action`
  - the exact tool_name Hermes passes for MCP tools (both prefix forms are matched)
"""

import datetime
import hashlib
import json
import os
import re
import time

# ============================================================================
# CONFIG: edit this section
# ============================================================================

# Set to "default" / "local" to override the automatic profile detection.
PROFILE = None

# --- APPROVE: these always need your yes in chat ---------------------------
# Phone tools from the Plivo plugin (F8: make_call in toolset plivo_make_call,
# send_sms in plivo_send_sms). call_place only matters if you build your own
# wrapper tool (notes #9 suggests that name).
CALL_TOOLS = {"make_call", "call_place"}
SMS_TOOLS = {"send_sms"}

# browser_vault (toolset browser) actions: list | fill | save_login | enter_code | unlock (F5).
# With a stored TOTP seed, enter_code is otherwise automatic ("Nobody is asked").
VAULT_TOOL = "browser_vault"
VAULT_APPROVE_ACTIONS = {"enter_code"}
# Card fills already need Hermes' own confirmation (F5); this adds a second,
# explicit prompt. Detected by a card-like word in the fill arguments (verify).
APPROVE_CARD_FILLS = True
CARD_HINT = re.compile(r"card|payment|credit|debit|visa|mastercard|amex", re.IGNORECASE)
# Set True to approve every vault fill (logins too). Noisy but strict.
APPROVE_ALL_VAULT_FILLS = False

# make_call: refuse unless the agent wrote a matching call brief first
# (templates/call-brief.yaml). The plugin runs on the host, so this is the host
# path of /workspace/work/calls/briefs inside each profile's sandbox
# (config/templates/default.config.yaml and local.config.yaml mounts).
REQUIRE_BRIEF_FOR_CALLS = True
BRIEF_DIRS = {
    "default": r"C:\agent\workspace\calls\briefs",
    "local": r"C:\agent\local\workspace\calls\briefs",
}
BRIEF_MAX_AGE_MINUTES = 120
# Candidate argument keys for the destination number (verify in Spike S12).
NUMBER_ARG_KEYS = ("to", "to_number", "destination", "number", "phone_number", "dst")
# Brief fields shown in the approval message, in this order.
BRIEF_FIELDS = (
    "callee", "relationship", "goal", "opening_line", "may_agree_to", "must_not",
    "info_allowed", "max_minutes", "if_voicemail", "if_asked_for_owner",
    "success_criteria",
)

# --- BLOCK: terminal command patterns that never run -----------------------
# Tool names and argument keys for shell-like tools, confirmed in P2.1 step 3 (cmd and
# script were never seen; kept, since an extra key only widens the check). Any tool whose
# args contain one of COMMAND_ARG_KEYS is checked too (browser_exec passes `code`).
TERMINAL_TOOLS = {"terminal", "execute_code"}
COMMAND_ARG_KEYS = ("command", "cmd", "code", "script")

BLOCK = [
    # D6: the agent mailbox is receive-only. Matches, for example:
    #   himalaya message send ... / message reply 12 / message forward 12 /
    #   message write / template send
    # Subcommand names: check `himalaya --help` in the sandbox (verify).
    # To also stop deletions, add "delete" to the second group.
    (r"\bhimalaya\b.*\b(message|template)\s+(send|reply|forward|write)\b",
     "The agent mailbox is receive-only (D6): Himalaya send/reply/forward/write is blocked."),
    # PLAN.md §6: the OTP folder is yours only. --folder is documented (F7); -f is a guess.
    (r"\bhimalaya\b.*(--folder|-f)[\s=]+[\"']?OTP\b",
     "The OTP folder is never read by the agent."),
    # Other ways to send mail from a shell (defence in depth for D6).
    (r"\b(sendmail|msmtp|swaks|mutt)\b|\bsmtplib\b|\bsmtps?://",
     "Sending mail from the sandbox is blocked (D6)."),
    # D6, AgentMail CLI (docs/verification-notes.md AM9). Both command forms: the Hermes skill
    # writes `agentmail inboxes:messages send`, the CLI reference `agentmail inboxes messages send`.
    # "reply" also matches reply-all.
    (r"\bagentmail\b.*\binboxes(?::|\s+)messages(?::|\s+)(send|reply|reply-all|forward)\b",
     "The agent mailbox is receive-only (D6): AgentMail send/reply/forward is blocked."),
    # Drafts: a draft created with send_at sends itself, so create/update/send are all blocked.
    (r"\bagentmail\b.*\b(inboxes|pods)(?::|\s+)drafts(?::|\s+)(create|update|send)\b",
     "The agent mailbox is receive-only (D6): AgentMail draft create/update/send is blocked."),
    # Agent sign-up and attach-human send OTP mail and can create a new AgentMail organization.
    (r"\bagentmail\b.*\bagent(?::|\s+)(sign-up|attach-human)\b",
     "AgentMail sign-up and attach-human are blocked (D6)."),
    # The same through AgentMail's REST API or SMTP from a shell (AM3, AM10).
    (r"\bapi\.agentmail\.(to|eu)/v0/\S*(/messages/send|/reply|/forward|/drafts)\b",
     "Sending through the AgentMail API is blocked (D6)."),
    (r"\bsmtp\.agentmail\.(to|eu)\b",
     "AgentMail SMTP is blocked (D6)."),
]

# --- BLOCK: MCP tools that send or schedule mail (D6) ------------------------
# Server-native names from AgentMail's MCP manifest (AM8). The relay's --tools filter and the
# scoped key's permissions already keep these out; this is the third layer (PLAN.md §6).
# Hermes registers MCP tools as mcp__<server>__<tool> (code: tools/mcp_tool_schema.py), while
# its feature docs show mcp_<server>_<tool>, so both prefix forms match, for any server name.
MAIL_SEND_MCP_TOOLS = {
    "send_message", "reply_to_message", "forward_message",
    "send_draft", "create_draft", "update_draft",
    "agent_attach_human",
}
# Unprefixed names are blocked too, except these: send_message is Hermes' own built-in
# messaging tool (tools/send_message_tool.py), which this plugin doesn't gate.
BARE_NAME_EXCEPTIONS = {"send_message"}

# Terminal commands matching this get an approval prompt (used by P2.1's test).
SELFTEST_PATTERN = r"\bapproval-selftest\b"

# --- DENY_LOG: one JSON line per block/approve decision --------------------
# Arg VALUES are not logged (they may hold personal data); only arg keys and
# the decision message (truncated).
DENY_LOG = r"C:\agent\shared\logs\policy-{profile}.jsonl"
# Set True for a day to log every tool call's name and arg keys. That's how
# you confirm TERMINAL_TOOLS, COMMAND_ARG_KEYS and NUMBER_ARG_KEYS.
LOG_ALL_TOOL_CALLS = False  # P2.1: was on for one day (steps 2-3)

# Keep approval prompts readable on a phone.
MAX_MESSAGE_CHARS = 1500

# ============================================================================
# Implementation
# ============================================================================

_BLOCK_RES = [(re.compile(p, re.IGNORECASE | re.DOTALL), msg) for p, msg in BLOCK]
_MAIL_MCP_RE = re.compile(
    r"^mcp_{1,2}[A-Za-z0-9_]+?_{1,2}(" + "|".join(sorted(map(re.escape, MAIL_SEND_MCP_TOOLS))) + r")$",
    re.IGNORECASE,
)
_SELFTEST_RE = re.compile(SELFTEST_PATTERN)
_PHONE_RE = re.compile(r"\+?\d[\d\s().-]{7,}\d")


def _profile():
    """Profile name: PROFILE, else from this file's path, else HERMES_HOME (F1)."""
    if PROFILE:
        return PROFILE
    for candidate in (os.path.abspath(__file__), os.environ.get("HERMES_HOME", "")):
        parts = [p for p in re.split(r"[\\/]+", candidate or "") if p]
        for i, part in enumerate(parts[:-1]):
            if part.lower() == "profiles":
                return parts[i + 1]
    return "default"


def _as_dict(args):
    if isinstance(args, dict):
        return args
    if isinstance(args, str):
        try:
            parsed = json.loads(args)
            if isinstance(parsed, dict):
                return parsed
        except ValueError:
            pass
        return {"_raw": args}
    return {}


def _strings(value):
    """Yield every string inside a nested args structure."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for k, v in value.items():
            yield str(k)
            yield from _strings(v)
    elif isinstance(value, (list, tuple)):
        for v in value:
            yield from _strings(v)
    elif value is not None:
        yield str(value)


def _command_text(tool_name, args):
    picked = [str(args[k]) for k in COMMAND_ARG_KEYS if k in args and args[k] is not None]
    if picked:
        return "\n".join(picked)
    if tool_name in TERMINAL_TOOLS:
        return "\n".join(_strings(args))
    return None


def _is_mail_send_tool(tool_name):
    """True for an MCP (or bare) tool name that sends or schedules mail."""
    name = str(tool_name or "")
    if _MAIL_MCP_RE.match(name):
        return True
    bare = name.lower()
    return bare in MAIL_SEND_MCP_TOOLS and bare not in BARE_NAME_EXCEPTIONS


def _digits(text):
    return re.sub(r"\D", "", str(text or ""))


def _numbers_in(args):
    found = []
    for key in NUMBER_ARG_KEYS:
        if key in args and _digits(args[key]):
            found.append(_digits(args[key]))
    if not found:
        plus, other = [], []
        for s in _strings(args):
            for m in _PHONE_RE.findall(s):
                d = _digits(m)
                if 8 <= len(d) <= 15:
                    (plus if m.startswith("+") else other).append(d)
        found = plus + other  # prefer E.164-looking strings over dates and IDs
    return found


def _same_number(a, b):
    return bool(a) and bool(b) and (a == b or a.endswith(b) or b.endswith(a))


def _load_yaml(text):
    try:
        import yaml  # PyYAML; present in most Hermes installs (verify)
        data = yaml.safe_load(text)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def _find_brief(number):
    """Newest brief in this profile's BRIEF_DIRS entry, younger than BRIEF_MAX_AGE_MINUTES, for this number."""
    brief_dir = BRIEF_DIRS.get(_profile(), BRIEF_DIRS["default"])
    if not os.path.isdir(brief_dir):
        return None, None, None
    cutoff = time.time() - BRIEF_MAX_AGE_MINUTES * 60
    candidates = []
    for name in os.listdir(brief_dir):
        if not name.lower().endswith((".yaml", ".yml")):
            continue
        path = os.path.join(brief_dir, name)
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime >= cutoff:
            candidates.append((mtime, path))
    for _, path in sorted(candidates, reverse=True):
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except OSError:
            continue
        data = _load_yaml(text)
        brief_number = ""
        if data and isinstance(data.get("callee"), dict):
            brief_number = _digits(data["callee"].get("number"))
        if not brief_number:
            brief_number = "".join(_digits(m) for m in _PHONE_RE.findall(text)[:1])
        if _same_number(brief_number, number):
            return path, data, text
    return None, None, None


def _fmt_value(value):
    if isinstance(value, dict):
        return ", ".join(f"{k}: {_fmt_value(v)}" for k, v in value.items())
    if isinstance(value, (list, tuple)):
        return "; ".join(_fmt_value(v) for v in value)
    return " ".join(str(value).split())


def _render_brief(path, data, text):
    lines = [f"Brief: {os.path.basename(path)}"]
    if data:
        for field in BRIEF_FIELDS:
            if field in data:
                lines.append(f"{field}: {_fmt_value(data[field])}")
    else:
        lines.append(text.strip())
    return "\n".join(lines)


def _render_args(args, limit=600):
    shown = {k: v for k, v in args.items() if k != "_raw"} or args
    return json.dumps(shown, default=str, ensure_ascii=False)[:limit]


def _rule_key(tool_name, args):
    # Unique per call, so an "always" answer can't pre-approve future calls.
    # (Whether rule_key persists into command_allowlist is unverified: F9.)
    digest = hashlib.sha256(
        (tool_name + json.dumps(args, sort_keys=True, default=str) + str(time.time())).encode()
    ).hexdigest()[:10]
    return f"policy:{tool_name}:{digest}"


def _approve(tool_name, args, message):
    return {
        "action": "approve",
        "message": message[:MAX_MESSAGE_CHARS],
        "rule_key": _rule_key(tool_name, args),
    }


def _block(message):
    return {"action": "block", "message": (message or "Blocked by approval-policy.")[:MAX_MESSAGE_CHARS]}


def _decide(tool_name, args):
    # 1. BLOCK beats everything: mail-sending MCP tools, then terminal command patterns.
    if _is_mail_send_tool(tool_name):
        return _block(f"The agent mailbox is receive-only (D6): {tool_name} is blocked.")
    command = _command_text(tool_name, args)
    if command:
        for regex, message in _BLOCK_RES:
            if regex.search(command):
                return _block(message)
        if _SELFTEST_RE.search(command):
            return _approve(tool_name, args, "approval-policy self-test: approve this harmless command?")

    # 2. Phone calls: show the brief, refuse without one.
    if tool_name in CALL_TOOLS:
        numbers = _numbers_in(args)
        if not numbers:
            if REQUIRE_BRIEF_FOR_CALLS:
                return _block(
                    f"{tool_name} blocked: no destination number found in its arguments "
                    f"(keys: {sorted(args)}). Update NUMBER_ARG_KEYS (Spike S12)."
                )
            return _approve(tool_name, args, f"Outbound phone call - approve?\nArgs: {_render_args(args)}")
        number = numbers[0]
        path, data, text = _find_brief(number)
        if path is None and REQUIRE_BRIEF_FOR_CALLS:
            return _block(
                f"{tool_name} to +{number} blocked: no call brief for this number in {BRIEF_DIRS.get(_profile(), BRIEF_DIRS['default'])} "
                f"from the last {BRIEF_MAX_AGE_MINUTES} minutes. Write one first (templates/call-brief.yaml)."
            )
        body = _render_brief(path, data, text) if path else "(no brief found)"
        return _approve(
            tool_name, args,
            f"Outbound phone call to +{number} - approve? Reply yes or no.\n{body}\nArgs: {_render_args(args, 300)}",
        )

    # 3. SMS: show destination and text.
    if tool_name in SMS_TOOLS:
        numbers = _numbers_in(args)
        to = f"+{numbers[0]}" if numbers else "(number not found)"
        return _approve(tool_name, args, f"Outbound SMS to {to} - approve? Reply yes or no.\nArgs: {_render_args(args)}")

    # 4. Vault: 2FA code entry and card fills.
    if tool_name == VAULT_TOOL:
        action = str(args.get("action", "")).lower()
        if action in VAULT_APPROVE_ACTIONS:
            return _approve(tool_name, args, f"2FA code entry ({action}) - approve?\nArgs: {_render_args(args, 300)}")
        if action == "fill":
            looks_like_card = any(CARD_HINT.search(s) for s in _strings(args))
            if APPROVE_ALL_VAULT_FILLS or (APPROVE_CARD_FILLS and looks_like_card):
                label = "Card fill" if looks_like_card else "Vault fill"
                return _approve(tool_name, args, f"{label} - approve?\nArgs: {_render_args(args, 300)}")

    return None


def _log(profile, tool_name, args, decision):
    """Append one JSON line. Never raises."""
    try:
        if decision is None and not LOG_ALL_TOOL_CALLS:
            return
        record = {
            "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            "profile": profile,
            "tool": tool_name,
            "arg_keys": sorted(str(k) for k in args) if isinstance(args, dict) else [],
            "action": decision.get("action") if decision else None,
            "rule_key": decision.get("rule_key") if decision else None,
            "message": (decision.get("message", "") if decision else "")[:200],
        }
        path = DENY_LOG.format(profile=profile)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception:
        pass


def gate(tool_name=None, args=None, task_id=None, **kwargs):
    """pre_tool_call callback. Returns a decision dict or None."""
    profile = "unknown"
    safe_args = {}
    try:
        profile = _profile()
        safe_args = _as_dict(args)
        decision = _decide(str(tool_name or ""), safe_args)
    except Exception as exc:  # fail closed, with a reason you can read
        decision = _block(f"approval-policy internal error ({type(exc).__name__}); call blocked (fail closed).")
    _log(profile, tool_name, safe_args, decision)
    return decision


def register(ctx):
    ctx.register_hook("pre_tool_call", gate)
