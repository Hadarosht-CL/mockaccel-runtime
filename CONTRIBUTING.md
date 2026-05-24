# Contributing to mockaccel-runtime

Thanks for your interest. This project is a small, deliberately-scoped mock embedded inference runtime, used as a test fixture for build and CI tooling. Contributions should preserve that focus — small, readable, and easy to test against.

## Ground rules

- All contributions are licensed under Apache-2.0 (see `LICENSE`).
- Every source file carries an `SPDX-License-Identifier: Apache-2.0` header. New files need one too.
- Be civil. See `CODE_OF_CONDUCT.md`.

## Building locally

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
See the top-level `README.md` for prerequisites and the smoke test.

## Branching

Trunk-based: `main` is always releasable. Work on short-lived feature branches named `feat/<topic>`, `fix/<topic>`, or `chore/<topic>`. Open a Merge Request against `main` — no direct pushes.

## Commit messages

We follow [Conventional Commits](https://www.conventionalcommits.org/). Format:
<type>: <subject>
Types in use: feat, fix, chore, docs, refactor, test, build, ci. Keep the subject under 72 characters and in the imperative mood ("add X", not "added X").

## Merge Request checklist

Before requesting review:
- Code builds cleanly with no new warnings.
- If you touched the wire protocol, docs/protocol.md reflects it.
- If you added a new fault type or op, both the daemon and the SDK changed.
- Commit messages follow the convention above.
- The MR description explains the why, not just the what.

## Reporting issues

Use the issue templates under .gitlab/issue_templates/.
For bugs, include: the command you ran, the daemon log output, and what you expected versus what happened.

