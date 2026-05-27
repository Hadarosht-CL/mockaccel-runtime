# CI design

This directory documents the project's CI (Continuous Integration)
architecture. The pipeline files themselves live at the repo root:

- `.gitlab-ci.yml` - GitLab CI pipeline.
- `Jenkinsfile`    - Jenkins declarative pipeline.

Both drive the same seven-stage flow by calling into `scripts/`.

## Architecture

Logic lives in `scripts/`. YAML and Groovy are dispatch only.

```
.gitlab-ci.yml ──┐
                 ├──► scripts/<verb>.sh ──► CMake / Ninja / Docker / Helm / ...
Jenkinsfile  ────┘
```

Every job's body is a single `./scripts/<verb>.sh` call. The CI
platform's job is to schedule, gate, and pass artifacts. The shell
scripts contain all real logic.

## Why this design

1. **No duplication.** A change in build behavior lands in one place
   - `scripts/build.sh` - and both pipelines pick it up.
2. **CI platforms are interchangeable.** Switching from GitLab CI to
   Jenkins (or to GitHub Actions, CircleCI, etc.) is a half-day port
   of the dispatch file. The scripts do not change.
3. **Local reproduction.** Developers run the same script CI runs
   (`./scripts/build.sh`). No YAML-only logic that only fires in CI.
4. **Diffable.** YAML / Groovy diffs stay small and structural;
   substantive changes appear in the script diffs.

## The seven stages

| # | Stage        | Verb                          | What it does                                  |
|---|--------------|-------------------------------|-----------------------------------------------|
| 1 | lint         | `lint.sh`                     | shellcheck + shfmt across scripts/            |
| 2 | build        | `build.sh`                    | CMake + Ninja host build                      |
| 3 | test         | `test.sh`                     | pytest + unit/integration (Stage 5 stub today)|
| 4 | cross-build  | `build.sh --target=aarch64`   | ARM64 cross-compile (Stage 4 stub today)      |
| 5 | package      | `package.sh`                  | tarball + wheel (Stage 7 stub today)          |
| 6 | publish      | `publish.sh`                  | push to artifact registry (Stage 7 stub today)|
| 7 | deploy       | `deploy.sh`                   | helm upgrade to k3s (Stage 9 stub today)      |

Plus a `release` job on `v*.*.*` tags that creates a GitLab Release
(Stage 10 will wire git-cliff for real CHANGELOG content).

## DAG (Directed Acyclic Graph) execution

The pipeline does not run strictly stage-by-stage. With `needs:`
(GitLab) and parallel agents (Jenkins), jobs start the moment their
dependencies finish:

```
lint ─► build ─┬─► test (matrix: Release, Debug) ─┐
               └─► cross-build ───────────────────┴─► package ─► publish ─► deploy
                                                                       │
                                                                       └─► release (v*.*.* only)
```

## Gating

| Job          | Runs on                                       |
|--------------|-----------------------------------------------|
| lint         | every push                                    |
| build        | every push                                    |
| test         | every push (parallel matrix over BUILD_TYPE)  |
| cross-build  | every push                                    |
| package      | every push                                    |
| publish      | main branch + v*.*.* tags                     |
| deploy       | v*.*.* tags only                              |
| release      | v*.*.* tags only                              |

GitLab uses `rules:` (modern replacement for deprecated `only/except`).
Jenkins uses `when { branch / tag }` blocks. Same gating, two syntaxes.

## GitLab CI vs Jenkins feature mapping

| Concept              | GitLab CI                | Jenkins (declarative)              |
|----------------------|--------------------------|------------------------------------|
| Pipeline definition  | `.gitlab-ci.yml`         | `Jenkinsfile`                      |
| Job / stage          | `job:` under `stages:`   | `stage('Name')` under `stages {}`  |
| Runner image         | `image: ubuntu:22.04`    | `agent { docker { image '...' }}`  |
| Inheritance / DRY    | `extends:`               | shared library / Prepare stage     |
| DAG execution        | `needs:`                 | stage order + parallel agents      |
| Matrix fan-out       | `parallel: matrix:`      | `matrix { axes { } }`              |
| Branch / tag gating  | `rules:` with `if:`      | `when { branch / tag }`            |
| Artifacts            | `artifacts: paths:`      | `archiveArtifacts`                 |
| Cache                | `cache: key: paths:`     | per-agent caching plugins          |
| Post-job hooks       | `after_script:`          | `post { always / failure }`        |
| Release page         | `release:` keyword       | gitlab-release plugin / curl       |

## Adding a new stage

1. Add a `scripts/<verb>.sh` (strict-mode, `--help`, distinct exit codes).
2. Add the verb to the `stages:` list in `.gitlab-ci.yml`.
3. Add a job calling `./scripts/<verb>.sh`.
4. Mirror the stage in `Jenkinsfile`.
5. Update the table above.

Do not put logic in YAML or Groovy. If you find yourself doing so,
stop and move it to the script.

## Local validation

```bash
# Shell scripts
./scripts/lint.sh

# .gitlab-ci.yml structural parse
ruby -ryaml -e "YAML.load_file('.gitlab-ci.yml'); puts 'yaml ok'"

# Full GitLab pipeline lint (requires glab CLI)
glab ci lint

# Jenkinsfile - ci.jenkins.io public validator now requires auth.
# Fallback: structural review against the Jenkins declarative-pipeline
# reference, or local check via:
npx --yes npm-groovy-lint Jenkinsfile
```

## CI minute budget

GitLab.com free tier: 400 CI minutes / month. Each pipeline run is
~3-4 minutes (lint ~30s, build ~90s, parallel test ~30s each, etc.).
Cap-friendly: ~100 runs / month before hitting the limit.
