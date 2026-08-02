# 08 — Prompts History & Handover Instructions

## Key Prompts Used During Development

### Handover Prompt (For New AI Assistant Sessions)
```text
This project already contains complete AI documentation.

Before writing any code:
1. Read every file inside AI_CONTEXT/.
2. Understand the architecture.
3. Understand previous decisions.
4. Understand current progress.
5. Understand pending work.

Do not change architecture unless necessary.
Continue exactly from the current project state.
Never regenerate completed work.
Never overwrite existing Firebase data.

After completing today's work, automatically update:
- CURRENT_STATUS.md
- BUG_LOG.md
- CHANGELOG.md
- TODO.md

Do not ask me to explain previous work unless documentation is inconsistent.
```
