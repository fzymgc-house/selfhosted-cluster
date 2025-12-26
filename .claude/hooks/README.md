# Claude Code Hooks

PreToolUse hooks that validate and constrain Claude Code behavior in this repository.

## Overview

| Hook | Purpose | Trigger |
|------|---------|---------|
| `bash_command_validator.py` | Enforce preferred CLI tools | Bash tool calls |
| `gremlin-heredoc-containment.py` | Prevent file-writing via Bash | Bash tool calls |

## Exit Code Semantics

Claude Code hooks use exit codes to control behavior:

| Exit Code | Behavior |
|-----------|----------|
| 0 | Allow tool call to proceed |
| 1 | Show stderr to user only (configuration/input error) |
| 2 | Block tool call, show stderr to Claude (behavioral correction) |

## Hooks

### bash_command_validator.py

Validates Bash commands against preferred tool rules:

| Blocked Pattern | Suggested Alternative | Rationale |
|-----------------|----------------------|-----------|
| `grep` | `rg` (ripgrep) | Faster, full replacement |
| `find -name` | `rg --files -g pattern` | Better performance |
| `rg --type <lang>` | `ast-grep -p pattern` | Semantic code search |

**Note:** The `rg --type` rule only blocks content searches. File listing modes (`--files`, `-l`) are allowed.

**Example blocked commands:**
```bash
grep -r "pattern" .                    # Use: rg "pattern"
find . -name "*.py"                    # Use: rg --files -g "*.py"
rg --type python "def main"            # Use: ast-grep -p "def main"
```

**Example allowed commands:**
```bash
rg "pattern"                           # ripgrep is preferred
rg --files --type python               # File listing allowed
some_command | rg "filter"             # rg for filtering is fine
```

### gremlin-heredoc-containment.py

Blocks attempts to write files via Bash instead of using the Write tool. Detects "gremlin behavior" - creative workarounds to avoid proper tooling.

**Severity Levels:**

| Level | Trigger | Description |
|-------|---------|-------------|
| 1 | Heredoc patterns | `cat <<EOF > file`, `tee` with heredoc |
| 2 | Sneaky workarounds | Python one-liners, base64 decode to file |

**Blocked patterns include:**
```bash
cat << 'EOF' > config.yaml             # Use Write tool
cat <<EOF | tee /etc/config            # Use Write tool
echo -e "line1\nline2" > file          # Use Write tool
python3 -c "Path('f').write_text(...)" # Use Write tool
base64 -d <<< "..." > file             # Use Write tool
```

**Why this exists:** Claude sometimes exhibits a preference for heredocs over the Write tool, even when the Write tool is cleaner and handles escaping properly. This hook enforces consistent file creation patterns.

## Configuration

Hooks are registered in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          ".claude/hooks/bash_command_validator.py",
          ".claude/hooks/gremlin-heredoc-containment.py"
        ]
      }
    ]
  }
}
```

## Development

### Running Hooks Manually

Hooks read JSON from stdin and write to stderr:

```bash
echo '{"tool_name": "Bash", "tool_input": {"command": "grep foo"}}' | \
  python .claude/hooks/bash_command_validator.py
echo $?  # 2 = blocked
```

### Testing Changes

```bash
# Lint with ruff
ruff check .claude/hooks/
ruff format --check .claude/hooks/

# Test specific patterns
echo '{"tool_name": "Bash", "tool_input": {"command": "rg pattern"}}' | \
  python .claude/hooks/bash_command_validator.py && echo "allowed"
```

### Adding New Rules

1. Add pattern to appropriate `*_PATTERNS` list
2. Update docstrings and this README
3. Test with sample inputs
4. Commit with clear description of what's blocked and why

## Troubleshooting

**Hook blocks legitimate command:**
- Check if there's an alternative tool that should be used
- If the block is incorrect, adjust the regex pattern
- Use more specific patterns to reduce false positives

**Hook doesn't trigger:**
- Verify hook is registered in `.claude/settings.json`
- Check hook has execute permissions (`chmod +x`)
- Ensure Python 3.12+ is available (uses `uv run --script`)
