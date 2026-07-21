---
name: ci-debugging
description: Rules for debugging CI failures, GitHub Actions, coverage thresholds, and avoiding speculative CI fixes. Activate when investigating CI build failures, setting up GitHub Actions, or working with Codecov/coverage.
---

# CI Debugging

## CI Failure Investigation

- **Read the FULL error output** from a failed CI run before forming any hypothesis. Use `gh run view <id> --log-failed` without grep filters first. The root cause is often buried in verbose output that keyword grepping misses.
- **Never push speculative CI fixes.** Each push triggers a 3-8 minute CI cycle. Before pushing, verify your hypothesis can be tested locally or confirmed from existing log data. Aim for 1-2 fix commits, not 5+.
- **Check for Git LFS and submodules** whenever you see "Couldn't check out revision" or "Could not resolve package dependencies" in SPM/xcodebuild. These are the #1 cause of CI-only checkout failures.
- **Verify GitHub Actions versions exist** before referencing them (e.g., `@v2`). Use the repo's releases page or `gh api repos/{owner}/{repo}/tags` to confirm.
- **Simulate CI metric extraction locally before optimizing.** Before spending effort to move a CI-enforced metric (coverage, lint score, build size), run the exact extraction command from the CI script against a local result bundle. Verify it (1) targets the intended data (e.g., app target vs. test target), (2) parses the correct field, and (3) produces a plausible number. One `grep | awk` simulation catches broken scripts that documentation and prior agent claims won't.

## Codecov

- Codecov is optional for this project. The 28% app-code coverage floor is enforced by a bash script in `ci.yml` (`Check Coverage Threshold` step) — no third-party service needed. This measures `Edge AI Lab.app` (not the test target). The floor is a regression guard; ~70% of executable lines are SwiftUI view body code that unit tests can't reach. Only set up Codecov if/when the project accepts external contributors who would benefit from PR coverage comments.

## CRITICAL: Exit Code Swallowing (July 2026)

**`ci.yml` has 5 instances of `xcodebuild ... 2>&1 | tail -N` that silently eat build/test failures.** The `tail` command always exits 0, masking xcodebuild's non-zero exit code. CI reports "green" even when builds fail.

- **Lines affected**: 56, 73, 170, 242, 287 in `ci.yml`
- **Fix**: Add `set -o pipefail` at the top of each `run:` block, or replace `| tail -N` with `| tee /tmp/build.log; tail -N /tmp/build.log`
- **Impact**: Until fixed, CI provides ZERO signal about build or test failures. All "green" runs must be manually verified by reading the full log.

## LiteRT-LM Binary Checksum Drift

Google periodically re-uploads LiteRT-LM release xcframework binaries at the same URLs with different content. When this happens:

1. CI fails with `artifact of binary target 'CLiteRTLM' has changed checksum`
2. The stale checkout is in the `.spm-packages` GHA cache (NOT in `~/Library/Caches/org.swift.swiftpm/`)
3. **Fix**: Bump the cache key version in `setup-tuist-project/action.yml` (e.g., `spm-v3` → `spm-v4`)
4. The cache-clearing step before `tuist generate` is belt-and-suspenders but NOT sufficient alone
5. `Package.resolved` is gitignored (inside `EdgeAILab.xcworkspace/`) — you cannot fix this by updating `Package.resolved`

## CudaBuild Plugin Validation

mlx-swift ships a CUDA build plugin (`CudaBuild`). On macOS CI runners (no CUDA), plugin validation fails:
```
Validate plug-in "CudaBuild" in package "mlx-swift"
** BUILD FAILED **
```
**Fix**: Add `-skipPackagePluginValidation` to xcodebuild commands in CI, OR wait for mlx-swift to conditionally include the plugin.

## Package.resolved Is Gitignored

`EdgeAILab.xcworkspace/` is in `.gitignore` because Tuist regenerates it. This means:
- `Package.resolved` is NOT version-controlled
- CI always resolves fresh from `Project.swift` requirements
- You cannot pin transitive dependencies via `Package.resolved`
- Dependency versions on CI may differ from local if `Project.swift` uses `.branch()` or `.upToNextMajor()`

