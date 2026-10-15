---
description: Run the BuddyVerse iOS QA agent team (static review + device-SDK build, no simulator) and record everything they find in CLAUDE.md's Known Issues section.
---

Run a full QA pass over the BuddyVerse iOS app using the specialist subagents defined in `.claude/agents/`, then consolidate their findings into `CLAUDE.md`. **Never use a simulator.**

## Steps

1. Read `CLAUDE.md` in full first.

2. Spawn these five agents **in parallel, in the foreground** and wait for all of them: `qa-build-lint`, `qa-navigation-flow`, `qa-game-logic`, `qa-multiplayer`, `qa-content`. Give each no extra instructions beyond its own definition, and tell them not to edit `CLAUDE.md`.

3. Deduplicate findings (note when two agents found the same bug).

4. Find or create a `## Known Issues` section at the end of `CLAUDE.md` with `### Open` and `### Fixed`, and append each new finding under Open as:

   ```markdown
   #### ISSUE-N: Short title
   - **Severity:** HIGH | MEDIUM | LOW
   - **Area:** build | navigation | game-logic | multiplayer | content
   - **File:** path/to/File.swift:line
   - **Found by:** qa-agent-name (YYYY-MM-DD)
   - **Description:** ...
   - **Suggested fix:** ...
   ```

   Number sequentially from the highest existing ISSUE-N; never reuse or renumber, never edit Fixed entries. Don't add anything for "no issues found".

5. Report open issues by severity to the user.
