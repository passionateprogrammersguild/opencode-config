# Factory Standards

These standards apply to every unit of factory work, in every project. They are the
floor, not the ceiling: when the host project's `AGENTS.md` exists, its conventions
win over anything here.

1. **Spec files are the single source of truth.** A unit's scope is exactly what its
   spec file says. If the spec is wrong or ambiguous, stop and report BLOCKED — never
   silently widen or shrink scope.
2. **Small, focused diffs.** Change only the files a unit's spec lists. No drive-by
   refactors, no reformatting of untouched code, no dependency bumps unless specified.
3. **Tests accompany behavior changes.** Every behavior change ships with a test that
   fails without the change. Bug fixes get a regression test first.
4. **Follow the host project.** Match its existing style, structure, and tooling.
   Discover build/test commands from `AGENTS.md` and package files; never invent a
   build step.
5. **No secrets in code.** Never hardcode keys, tokens, passwords, or connection
   strings. Never print secret values in logs, commits, or reports. Read `.env` files
   only when a spec requires it.
6. **Conventional commit messages.** `feat:`, `fix:`, `test:`, `docs:`, `refactor:`,
   `chore:` — one logical change per commit, committed incrementally on the unit branch.
7. **Honest reporting.** Report what was actually run and what actually passed. An
   empty findings list means you found nothing, not that you looked nowhere.
