<!-- MR title format: <type>: <short subject>  (Conventional Commits) -->

## Summary
<!-- One or two sentences. What does this MR change? -->

## Why
<!-- The motivation. What problem does this solve, or what does it unlock? -->

## How tested
<!--
Paste the commands you ran. At a minimum:
  ./scripts/lint.sh        # shellcheck + shfmt across scripts/
  ./scripts/test.sh        # every registered test suite

Add anything else that exercised the change: a real build, an example
script, a manual check. Short output snippets welcome when they prove
something the reviewer can't easily check themselves.
-->

## Checklist
- [ ] `./scripts/lint.sh` exits 0
- [ ] `./scripts/test.sh` exits 0
- [ ] Builds cleanly with no new warnings
- [ ] Commit messages follow Conventional Commits
- [ ] `docs/protocol.md` updated if the wire protocol changed
- [ ] Daemon and SDK changed together if a new op or fault type was added
- [ ] README updated if user-visible behavior changed
