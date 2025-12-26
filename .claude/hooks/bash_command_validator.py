#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.12"
# ///
# ruff: noqa: T201
"""Bash command validator hook for Claude Code.

This hook runs as a PreToolUse hook for the Bash tool.
It validates bash commands against a set of rules before execution:

1. Blocks grep (suggests rg instead)
2. Blocks find -name (suggests rg --files instead)
3. Blocks rg --type <lang> for source code searches (suggests ast-grep instead)
   - Only blocks content searches, NOT file listing (--files, -l)
   - Supported languages: Swift, Python, TypeScript, JavaScript, Rust, Go,
     C, C++, HTML, Java, Kotlin, Ruby

Read more about hooks here: https://docs.anthropic.com/en/docs/claude-code/hooks
"""

import json
import re
import sys

# Supported ast-grep languages (for documentation and pattern building)
_AST_GREP_EXTENSIONS = r"swift|py|ts|js|jsx|tsx|rs|go|c|cpp|html|java|kt|rb"
_AST_GREP_TYPES = r"swift|python|typescript|javascript|rust|go|c|cpp|html|java|kotlin|ruby"

# Define validation rules as a list of (regex pattern, message) tuples
_VALIDATION_RULES = [
    (
        r"^grep\b(?!.*\|)",
        "Use 'rg' (ripgrep) instead of 'grep' for better performance and features",
    ),
    (
        r"^find\s+\S+\s+-name\b",
        "Use 'rg --files | rg pattern' or 'rg --files -g pattern' instead of 'find -name' for better performance",
    ),
    # Block rg content searches with --type for source code (ast-grep handles these better)
    # Does NOT match: rg --files, rg --files -g, rg -l (file listing modes)
    (
        rf"^rg\b(?!.*\s--files\b)(?!.*\s-l\b).*--type\s+({_AST_GREP_TYPES})\b",
        "Use 'sg -p pattern' or 'ast-grep -p pattern' instead of 'rg --type' for source code searches",
    ),
]


def _validate_command(command: str) -> list[str]:
    """Validate a command against the rules."""
    issues = []
    for pattern, message in _VALIDATION_RULES:
        if re.search(pattern, command):
            issues.append(message)
    return issues


def main() -> None:
    """Run the hook."""
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        # Exit code 1 shows stderr to the user but not to Claude
        sys.exit(1)

    tool_name = input_data.get("tool_name", "")
    if tool_name != "Bash":
        sys.exit(0)

    tool_input = input_data.get("tool_input", {})
    command = tool_input.get("command", "")

    if not command:
        sys.exit(0)

    issues = _validate_command(command)
    if issues:
        for message in issues:
            print(f"• {message}", file=sys.stderr)
        # Exit code 2 blocks tool call and shows stderr to Claude
        sys.exit(2)

    # Exit code 0 allows the tool call to proceed
    sys.exit(0)


if __name__ == "__main__":
    main()
