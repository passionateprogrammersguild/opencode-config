---
description: Score the most recent factory run
agent: build
---

Write score.md into the MOST RECENT run directory under ~/.opencode/factory/runs/
(according to the run-record schema): score is $1 on a 1-5 scale, notes are: $2
If $2 is empty, omit the notes field. Confirm the run id and project you scored.
If $1 is not a number 1-5, do nothing and say so.
