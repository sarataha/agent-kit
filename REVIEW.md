# Review

Failure here looks like: a hook lets through what it says it blocks, a gate that can be switched off by the change it judges, or a skill rule that contradicts another one.
Evidence: file:line, never a guess from a name. Start with the count of findings; say "nothing to fix" when there is none. At most 3 nits.

## Checklist

- When a hook changes: try one input it must deny and one it must allow; a denial uses `permissionDecision`, a PostToolUse message to Claude uses stderr and exit 2.
- When a file a gate reads changes (`.claude/ship-acceptance.json`, `AGENTS.md`, `REVIEW.md`): the session being judged can't edit it, or the gate reads it from the base branch or git history. A field the session writes about itself (`reviewed`) may add a warning, never clear one.
- When a skill gains a rule: it lives in one place; other skills point to it.
- When a shipped file changes: no owner-specific value (user, home path, employer); use `{{OWNER}}` and `{{PROJECTS}}`.
