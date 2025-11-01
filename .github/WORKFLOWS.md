# GitHub Workflows

This repository uses GitHub Actions for automated PR validation and GitHub Copilot for AI code reviews.

## Active Workflows

### PR Review (`pr-review.yml`)

Automated validation and labeling for pull requests.

**Triggers**: PR opened, synchronized, reopened

**Jobs**:

1. **Validate** - YAML file validation
   - Detects changed YAML/YML files
   - Runs `yamllint` with custom rules
   - Ensures configuration files are valid

2. **Label** - Auto-label PRs by changed files
   - Documentation (`*.md`)
   - Kubernetes manifests
   - Terraform files
   - Ansible playbooks
   - GitHub Actions
   - Dependencies

3. **Size** - Label PRs by change size
   - `size/small` - < 100 lines
   - `size/medium` - 100-500 lines
   - `size/large` - 500-1000 lines
   - `size/xlarge` - > 1000 lines

## GitHub Copilot Integration

This repository has GitHub Copilot enabled for AI-powered code reviews.

**To request a Copilot review**:
- Add a comment on the PR: `@copilot review`
- Or use the GitHub UI to request a Copilot review

**What Copilot reviews**:
- Code quality and best practices
- Potential bugs and errors
- Security vulnerabilities
- Performance issues
- Documentation completeness

## Workflow Maintenance

### Customizing Auto-Labels

Edit `.github/labeler.yml` to add or modify label patterns:

```yaml
custom-label:
  - changed-files:
    - any-glob-to-any-file: 'path/to/files/**/*'
```

### Adjusting YAML Validation Rules

Modify the yamllint configuration in `.github/workflows/pr-review.yml:39`:

```yaml
yamllint -d "{extends: default, rules: {your-rules-here}}" "$file"
```

### Changing Size Thresholds

Update line counts in `.github/workflows/pr-review.yml:78-80`:

```javascript
if (total > 1000) size = 'xlarge';
else if (total > 500) size = 'large';
else if (total > 100) size = 'medium';
```

## Best Practices

1. **Use labels** - They help organize and filter PRs
2. **Keep PRs small** - Aim for `size/small` or `size/medium`
3. **Request Copilot reviews** - For complex changes or when unsure
4. **Fix YAML errors** - Before merging, ensure validation passes
5. **Review Copilot feedback** - AI suggestions should be verified by humans
