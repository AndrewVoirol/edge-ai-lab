# LiteRT-LM Dependency: Known Limitations & Workarounds

> **Status**: Active constraint — all LiteRT-LM releases require `unsafeFlags`
> **Last reviewed**: 2026-06-10
> **Upstream**: [google-ai-edge/LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)

## The Constraint

LiteRT-LM's `Package.swift` contains:

```swift
linkerSettings: [
    .unsafeFlags(["-Xlinker", "-all_load"])
]
```

This is technically **required** — LiteRT-LM uses C++ static initializers to register GPU/CPU backends at startup. Without `-all_load`, the linker strips these "unused" symbols during optimization, causing a runtime crash: `Engine type not found: 1`.

## Why This Blocks Pinning

| Approach | Status | Why It Fails |
|----------|--------|--------------|
| `.upToNextMajor(from:)` | ❌ | SPM blocks `unsafeFlags` in remote package dependencies |
| `.exact("0.13.1")` | ❌ | Same — every tag (v0.12.0 → v0.13.1) uses `unsafeFlags` |
| `.revision("abc123")` | ❌ | LiteRT-LM's `main` branch has force-push history; SPM can't check out individual commits |
| `.branch("main")` | ✅ | Works — bypasses `unsafeFlags` restriction since branch deps are treated differently |

## Current Mitigation

1. **`Project.swift`** uses `.branch("main")`:
   ```swift
   .remote(url: "https://github.com/google-ai-edge/LiteRT-LM.git", requirement: .branch("main"))
   ```

2. **`.package.resolved` is gitignored** because pinned revisions become unreachable after force-pushes.

3. **CI pre-clones LiteRT-LM as a bare mirror** to work around GHA-specific SPM resolution failures (see `.github/actions/setup-tuist-project/action.yml`).

## Impact

- Every `tuist generate` or SPM resolution picks up whatever the latest commit on `main` is.
- Builds are not hermetically reproducible — different builds may get different LiteRT-LM commits.
- Force-pushes to `main` can break CI builds until the SPM cache is invalidated.

## Potential Future Resolutions

1. **Swift 6.2+**: Active Swift Evolution discussions about relaxing/removing the `unsafeFlags` restriction for remote dependencies. This would allow pinning to tagged versions.

2. **Upstream fix**: LiteRT-LM team could move `-all_load` from `Package.swift` to documentation, asking consumers to add it to their app's `OTHER_LDFLAGS`.

3. **Fork approach**: Fork LiteRT-LM, remove `unsafeFlags`, and add `-all_load` to our Tuist build settings. Trades instability for maintenance burden.

## References

- [Project.swift L27-31](Project.swift#L27-L31) — dependency declaration with rationale comments
- [.gitignore L11-14](.gitignore#L11-L14) — Package.resolved exclusion rationale
- [.github/actions/setup-tuist-project/action.yml](.github/actions/setup-tuist-project/action.yml) — bare mirror pre-clone workaround
