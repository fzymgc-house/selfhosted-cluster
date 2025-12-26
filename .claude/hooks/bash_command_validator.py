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

# Supported ast-grep language types for --type flag matching
_AST_GREP_TYPES = r"swift|python|typescript|javascript|rust|go|c|cpp|html|java|kotlin|ruby"

# Maximum characters to show in error message previews
_ERROR_PREVIEW_MAX_CHARS = 200

# Define validation rules as a list of (regex pattern, message) tuples
_VALIDATION_RULES = [
    # Block grep anywhere in command - rg is a full replacement
    # Matches: grep, cmd | grep, cmd && grep, etc.
    (
        r"\bgrep\b",
        "Use 'rg' (ripgrep) instead of 'grep' - it's faster and a full replacement",
    ),
    # Block find -name anywhere in command (word boundary for consistency with grep rule)
    (
        r"\bfind\s+\S+\s+-name\b",
        "Use 'rg --files | rg pattern' or 'rg --files -g pattern' instead of 'find -name' for better performance",
    ),
    # Block rg content searches with --type for source code (ast-grep handles these better)
    # Pattern uses negative lookahead (?!...) to ALLOW file listing modes:
    #   --files: lists matching files without content
    #   -l: prints only filenames (like --files-with-matches)
    # Uses start anchor (^) because rg must be the primary command for this check
    (
        rf"^rg\b(?!.*\s--files\b)(?!.*\s-l\b).*--type\s+({_AST_GREP_TYPES})\b",
        "Use 'sg -p pattern' or 'ast-grep -p pattern' instead of 'rg --type' for source code searches",
    ),
]


def _validate_command(command: str) -> list[str]:
    """Validate a command against the rules.

    Args:
        command: The bash command string to validate.

    Returns:
        List of validation error messages (empty if command passes all checks).

    Raises:
        SystemExit: If a regex pattern is malformed (configuration error).

    """
    issues = []
    for pattern, message in _VALIDATION_RULES:
        try:
            if re.search(pattern, command):
                issues.append(message)
        except re.error as e:
            print(f"Hook config error: Invalid regex '{pattern}': {e}", file=sys.stderr)
            sys.exit(1)
    return issues


def main() -> None:
    """Run the hook."""
    # Read stdin first for better error context
    raw_input = sys.stdin.read()
    try:
        input_data = json.loads(raw_input)
    except json.JSONDecodeError as e:
        preview = raw_input[:_ERROR_PREVIEW_MAX_CHARS] + "..." if len(raw_input) > _ERROR_PREVIEW_MAX_CHARS else raw_input
        print(f"Error: Invalid JSON input: {e}\nReceived: {preview}", file=sys.stderr)
        # Exit code 1 shows stderr to the user but not to Claude
        sys.exit(1)

    tool_name = input_data.get("tool_name", "")
    if tool_name != "Bash":
        sys.exit(0)

    tool_input = input_data.get("tool_input", {})
    if not isinstance(tool_input, dict):
        print(f"Error: Expected tool_input to be dict, got {type(tool_input).__name__}", file=sys.stderr)
        sys.exit(1)

    command = tool_input.get("command", "")

    if not command:
        sys.exit(0)

    issues = _validate_command(command)
    if issues:
        for message in issues:
            print(f"• {message}", file=sys.stderr)
        # Exit code 2 blocks tool call and shows stderr to Claude
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
