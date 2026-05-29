# PR Reviewability Checklist

Walk this checklist when diagnosing whether a PR is ready for review. Each item
lists a concrete check. Use `ck_validate` for automated scanning, then manually
verify items requiring judgment.

## Commit History

- **Single-intent commits**: Each commit should express one coherent change. If a commit mixes schema changes, UI tweaks, and test updates, flag it for splitting.
- **Descriptive subjects**: Every commit subject should answer "what does this change?" without opening the diff. Avoid subjects like "fix", "update", or "wip".
- **Dependency order**: Commits should follow a logical order: schema → service → API → UI → tests. Out-of-order commits make the reviewer reconstruct the timeline.
- **No dead commits**: Reverted commits, "fix previous commit", or "oops" commits add noise. Squash or reorder before review.

## PR Description

- **TL;DR present**: One sentence describing the diff's purpose, matching the actual changes.
- **Core files listed**: The 3-7 files a reviewer should read carefully, separated from mechanical changes.
- **Risk callouts**: Migration order, behavior changes, rollout dependencies, or missing test coverage.
- **Context links**: Issue tracker, design doc, dashboard, or prior PR that explains the intent.
- **Testing instructions**: How to verify the change locally (commands, seed data, specific routes).

## Diff Structure

- **Mechanical vs logic separation**: Formatting, generated files, or boilerplate should be in separate commits from logic changes. Reviewers should not hunt for the real change.
- **Unrelated changes removed**: If the branch contains changes for a different feature or fix, move them to a separate branch.
- **Test coverage**: Core logic changes must have corresponding test changes. If tests are missing, flag it as a reviewability issue.
- **File count reasonable**: More than 15 changed files signals the PR may need splitting. More than 30 is a strong signal to split.

## Reviewer Entry Points

- **Main entry file identified**: Which file should the reviewer read first? Add this to the PR description.
- **Complex sections annotated**: Non-obvious algorithms, workarounds, or trade-offs should have inline comments explaining the "why".
- **Migration safety**: If the PR includes migrations, note the rollback plan and any data migration concerns.

## Blocking Conditions

Do not proceed with reviewability improvements if:

- `ck_validate` returns blocked findings — fix those first
- The PR contains behavior changes hidden as cleanup
- The tree hash changes after history cleanup (content was accidentally modified)
- The branch depends on unmerged work from another branch
