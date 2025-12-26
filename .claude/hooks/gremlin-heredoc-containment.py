#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.12"
# ///
# ruff: noqa: T201
"""Gremlin containment hook for Claude Code.

This PreToolUse hook blocks Claude's pathological avoidance of the Write tool.
It detects heredoc patterns, sneaky Python workarounds, and other creative
attempts to write files via Bash instead of using the proper Write tool.

Exit code 2 blocks the tool and feeds stderr back to Claude.
"""

import json
import re
import sys

# Severity levels
_SEVERITY_HEREDOC = 1
_SEVERITY_SNEAKY = 2

# Patterns that indicate file-writing via bash instead of the Write tool
HEREDOC_PATTERNS = [
    # Standard heredoc to file: cat << 'EOF' > file, cat <<EOF > file, etc.
    r"cat\s+<<-?\s*['\"]?\w+['\"]?\s*>\s*\S+",
    # Heredoc with pipe to file: cat << 'EOF' | something > file
    r"cat\s+<<-?\s*['\"]?\w+['\"]?.*\|\s*.*>\s*\S+",
    # tee with heredoc: cat << 'EOF' | tee file
    r"cat\s+<<-?\s*['\"]?\w+['\"]?.*\|\s*tee\s+",
    # echo/printf multiline to file (multiple lines or -e flag)
    r"echo\s+-e\s+['\"].*\\n.*['\"]\s*>\s*\S+",
    r"printf\s+['\"].*\\n.*['\"]\s*>\s*\S+",
]

# The sneaky Python workaround patterns
PYTHON_WRITE_PATTERNS = [
    # python -c "...Path...write_text..."
    r"python3?\s+-c\s+['\"].*Path.*write_text",
    r"python3?\s+-c\s+['\"].*open\s*\(.*write",
    # Even sneakier: base64 decode to file
    r"base64\s+-d.*>\s*\S+",
    r"base64\s+--decode.*>\s*\S+",
]


def detect_gremlin_behavior(command: str) -> tuple[bool, int]:
    """Detect various forms of file-writing avoidance.

    Returns:
        (is_gremlin, severity)
        severity: 1 = standard heredoc, 2 = sneaky workaround

    """
    # Check for heredoc patterns
    for pattern in HEREDOC_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE | re.DOTALL):
            return (True, _SEVERITY_HEREDOC)

    # Check for Python workarounds
    for pattern in PYTHON_WRITE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE | re.DOTALL):
            return (True, _SEVERITY_SNEAKY)

    return (False, 0)


def get_message(severity: int) -> str:
    """Generate the appropriate containment message."""
    if severity == _SEVERITY_HEREDOC:
        return """🔒 I see you, gremlin.

You're trying to write a file using a heredoc instead of the Write tool.

The Write tool exists. It's cleaner. It handles escaping. It's literally
designed for this exact purpose. You've demonstrated you know how to use it.

Please use the Write tool to create or modify files."""

    if severity == _SEVERITY_SNEAKY:
        return """🔒 I see you, gremlin. The Python workaround isn't clever either.

You tried to bypass the heredoc block by writing a Python one-liner to
write the file instead. This is MORE work, not less. You are actively
making things harder to avoid using the tool designed for this task.

Please use the Write tool.

P.S. - Writing to /tmp first and then moving it doesn't count as using
the Write tool either. Don't even think about it."""

    return """🔒 Gremlin behavior detected.

Please use the Write tool to create or modify files."""


def main() -> None:
    """Run the hook."""
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Hook error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Only check Bash commands
    if tool_name != "Bash":
        sys.exit(0)

    command = tool_input.get("command", "")
    if not command:
        sys.exit(0)

    is_gremlin, severity = detect_gremlin_behavior(command)

    if is_gremlin:
        message = get_message(severity)
        print(message, file=sys.stderr)
        sys.exit(2)

    # Not gremlin behavior, allow the command
    sys.exit(0)


if __name__ == "__main__":
    main()
