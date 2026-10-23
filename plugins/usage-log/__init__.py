r"""usage-log: per-call model/provider log for Hermes Agent.

Built from the documented hook contract; both hook names exist in Hermes v0.22.4.
installer/steps/08-plugins.ps1 installs it; verify/checks/p1-5-usage-log.ps1 checks a real line.

Hook used (docs/verification-notes.md F10): the observer hook post_api_request,
which receives session_id, platform, model, provider, base_url, api_call_count,
api_duration, response_model, finish_reason, usage, context_length.
api_request_error (fires on failures, with status and retry timing) is also
logged when LOG_ERRORS is True; its argument names are not in the notes, so
every simple keyword it passes is recorded.

Each model call becomes one JSON line in LOG_PATH, e.g.
  {"ts": "...", "profile": "private", "model": "...", "provider": "custom",
   "base_url": "http://localhost:11434/v1", "local": true, "tokens": {...}, ...}
`local` is true only when the base_url host is localhost, 127.0.0.1 or ::1.
A missing base_url counts as NOT local, so gaps show up in the privacy check.

This plugin only observes; it never blocks and never raises.

Install (Windows native). Plugin folders per F9; the profile path follows F1 (verify):
  default profile:  %LOCALAPPDATA%\hermes\plugins\usage-log\
  private profile:  %LOCALAPPDATA%\hermes\profiles\private\plugins\usage-log\
Plugins are off until enabled. Enable, then restart the gateway:
  hermes plugins enable usage-log
  hermes -p private plugins enable usage-log
  hermes gateway restart
"""

import datetime
import json
import os
import re
from urllib.parse import urlparse

# ============================================================================
# CONFIG
# ============================================================================

# Set to "default" / "private" to override the automatic profile detection.
# Automatic detection reads this file's path, then HERMES_HOME (F1). In a
# multiplexed gateway (F1) HERMES_HOME may not identify the profile; the
# hermes_home field in each line shows what was seen (verify in P1.5).
PROFILE = None
LOG_PATH = r"C:\agent\shared\logs\usage-{profile}.jsonl"
LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}
LOG_ERRORS = True

# ============================================================================
# Implementation
# ============================================================================


def _profile():
    if PROFILE:
        return PROFILE
    for candidate in (os.path.abspath(__file__), os.environ.get("HERMES_HOME", "")):
        parts = [p for p in re.split(r"[\\/]+", candidate or "") if p]
        for i, part in enumerate(parts[:-1]):
            if part.lower() == "profiles":
                return parts[i + 1]
    return "default"


def _is_local(base_url):
    try:
        host = urlparse(str(base_url)).hostname if base_url else None
        return bool(host) and host.lower() in LOCAL_HOSTS
    except Exception:
        return False


def _pick(obj, *names):
    """First non-None field from a dict or an object."""
    for name in names:
        try:
            value = obj.get(name) if isinstance(obj, dict) else getattr(obj, name, None)
        except Exception:
            value = None
        if value is not None:
            return value
    return None


def _tokens(usage):
    if usage is None:
        return None
    try:
        inp = _pick(usage, "input_tokens", "prompt_tokens")
        out = _pick(usage, "output_tokens", "completion_tokens")
        total = _pick(usage, "total_tokens")
        if total is None and isinstance(inp, (int, float)) and isinstance(out, (int, float)):
            total = inp + out
        # Prompt caching: "input" can exclude tokens served from the provider's cache (total = input +
        # output + cached), so log the cache fields too. Names vary by provider and Hermes version.
        details = _pick(usage, "prompt_tokens_details", "input_tokens_details")
        cache_read = _pick(usage, "cache_read_tokens", "cache_read_input_tokens", "cached_tokens")
        if cache_read is None and details is not None:
            cache_read = _pick(details, "cached_tokens", "cache_read_tokens")
        cache_write = _pick(usage, "cache_write_tokens", "cache_creation_input_tokens", "cache_creation_tokens")
        result = {"input": inp, "output": out, "total": total, "cache_read": cache_read, "cache_write": cache_write}
        if cache_read is None and isinstance(total, (int, float)) and isinstance(inp, (int, float)) and isinstance(out, (int, float)):
            unaccounted = total - inp - out
            if unaccounted > 0:
                result["unaccounted"] = unaccounted   # likely cached tokens under a field name we don't know
                try:
                    keys = usage.keys() if isinstance(usage, dict) else vars(usage).keys()
                    result["usage_keys"] = sorted(str(k) for k in keys)[:30]
                except Exception:
                    pass
        return result
    except Exception:
        return None


def _write(record):
    try:
        path = LOG_PATH.format(profile=record.get("profile", "unknown"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, default=str, ensure_ascii=False) + "\n")
    except Exception:
        pass


def _base(event, kwargs):
    base_url = kwargs.get("base_url")
    return {
        "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "event": event,
        "profile": _profile(),
        "hermes_home": os.environ.get("HERMES_HOME"),
        "session_id": kwargs.get("session_id"),
        "platform": kwargs.get("platform"),
        "model": kwargs.get("model"),
        "provider": kwargs.get("provider"),
        "base_url": base_url,
        "local": _is_local(base_url),
    }


def on_api_request(*args, **kwargs):
    try:
        record = _base("call", kwargs)
        record.update({
            "response_model": kwargs.get("response_model"),
            "api_call_count": kwargs.get("api_call_count"),
            "duration": kwargs.get("api_duration"),  # units as Hermes reports them (verify)
            "finish_reason": kwargs.get("finish_reason"),
            "context_length": kwargs.get("context_length"),
            "tokens": _tokens(kwargs.get("usage")),
        })
        _write(record)
    except Exception:
        pass


def on_api_error(*args, **kwargs):
    try:
        record = _base("error", kwargs)
        for key, value in kwargs.items():
            if key not in record and (value is None or isinstance(value, (str, int, float, bool))):
                record[key] = value
        _write(record)
    except Exception:
        pass


def register(ctx):
    try:
        ctx.register_hook("post_api_request", on_api_request)
    except Exception:
        pass
    if LOG_ERRORS:
        try:
            ctx.register_hook("api_request_error", on_api_error)
        except Exception:
            pass
