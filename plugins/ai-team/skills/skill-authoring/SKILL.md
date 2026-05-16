---
name: skill-authoring
description: Use when authoring a new SKILL.md for this plugin or any Claude Code plugin. Covers frontmatter format, required sections, naming conventions, progressive disclosure, and the quality bar that distinguishes a useful skill from noise.
---

# Skill authoring (meta-skill)

## When to consult

- Adding a new skill to this plugin.
- Reviewing a skill PR for quality.
- Deciding whether a new piece of knowledge should be a skill, an agent prompt addition, or a standards doc.

## What a skill is for

A skill captures **stack-specific or pattern-specific knowledge** that Claude should consult on-demand, not bake into every conversation. The bar is "would a competent engineer hit this gotcha within their first few hours on the stack? If yes — it's a skill."

Skills are NOT for:
- General programming wisdom (that's training).
- Project-specific business logic (that's project CLAUDE.md).
- Architectural decisions (those are ADRs).
- Operational standards (those are standards-* skills, derived from `docs/standards/`).

## File layout

```
plugins/ai-team/skills/<kebab-name>/
├── SKILL.md           ← required, with frontmatter
├── <supporting>.md    ← optional reference files
└── scripts/           ← optional helper scripts
```

The directory name becomes the skill's namespaced ID: `<plugin>:<skill-name>`. The `name:` frontmatter must match the directory name.

## Required frontmatter

```yaml
---
name: <kebab-case-name>
description: Use when [trigger conditions]. Covers [main topics].
---
```

- `name`: MUST match directory name exactly. Kebab-case, no underscores.
- `description`: Tells Claude WHEN to consult this skill. Lead with "Use when" — the model uses this to decide whether to load the skill. Be concrete about triggers (file types, package names, error messages). Vague descriptions get ignored.

Optional frontmatter (per Anthropic docs):
- `disable-model-invocation: true` — skill is only invoked when user types `/plugin:skill-name`, never auto-invoked. Use for slash-command-only skills.

## Required body sections

```markdown
# <Stack name>

## When to consult

[Concrete trigger conditions — be specific about file paths, package names, observable symptoms]

## Gotchas

### <Gotcha title>
**Symptom:** [what the engineer sees that's wrong]
**Root cause:** [why it happens]
**Fix:** [the specific remediation]

### <Next gotcha>
...

## Conventions

[Project-wide conventions for this stack — defaults to follow, things to never do]

## See also

- [[other-related-skill]]
- ADR-NNNN (if relevant)
```

## Quality bar

A useful skill answers: **"What does this stack/pattern know that I'd hit my head on otherwise?"**

Each gotcha must include:
1. **A concrete symptom** (what fails, where, with what error).
2. **The root cause** (why the symptom appears).
3. **The fix** (specific code or config change).

If you can't write all three for a gotcha, you don't know it well enough yet — leave it out until you do.

## Progressive disclosure

If the full content is long (> ~150 lines), put a summary in `SKILL.md` and use `${CLAUDE_PLUGIN_ROOT}/skills/<name>/<supporting>.md` references so Claude can Read the deep content on demand. The standards-* skills in this plugin use this pattern: terse SKILL.md, full standard text in a sibling `standard.md`.

## When to UPDATE vs CREATE

- **Update an existing skill** when adding a new gotcha or convention to the same stack/pattern.
- **Create a new skill** when the topic is genuinely a different stack/pattern (don't conflate "Next.js" and "Next.js + Turbopack" — split them).

## See also

- [Anthropic's Skill docs](https://code.claude.com/docs/en/skills)
- The standards-* skills in this plugin as a "progressive disclosure with bundled supporting file" example
- [[nextjs-turbopack]] as a "tight, gotcha-focused" example
