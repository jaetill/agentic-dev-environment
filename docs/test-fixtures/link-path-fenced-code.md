# Fixture: fenced code block link-path check

This file is a regression fixture for `scripts/validate-platform.sh` (issue #110).
A fenced code block below contains a markdown link that references a path that does
not exist on disk. The link-path integrity check must skip it — it is prose inside
a code fence, not a real cross-reference — so the validator must exit 0.

```markdown
See the guide at [Getting Started](nonexistent-example.md) for details.
```

Links outside fences are still checked normally:
[validate-platform script](../../scripts/validate-platform.sh)
