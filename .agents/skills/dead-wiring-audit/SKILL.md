---
name: dead-wiring-audit
description: Systematic audit for unreachable UI, dead code, and orphan views. Activate after major refactors, before releases, or when the user reports "buttons that don't work" or "features I can't find."
---

# Dead Wiring Audit

A dead wire is a code path where the **handler exists but the trigger is unreachable** — the action code is present, but the user has no way to invoke it. This is worse than a compile error because it compiles fine, ships silently, and erodes trust when users can't find features.

## When to Run

- After major refactors that change navigation or feature access patterns
- Before releases or milestone checkpoints
- When the user reports "I can't find X" or "this button does nothing"
- After removing or replacing views

## Audit Categories

### 1. Sheet/Alert Triggers

Find all `.sheet()` and `.alert()` modifiers, then verify something sets their `isPresented` binding or `item` binding to a non-nil value:

```bash
# Find all sheet presentations
grep -rn '\.sheet(' Sources/ --include='*.swift' | grep -v 'Preview\|#Preview'

# Find all alert presentations
grep -rn '\.alert(' Sources/ --include='*.swift' | grep -v 'Preview\|#Preview'
```

For each hit, identify the `@State` or `@Binding` variable, then grep for all locations that set it to `true` or non-nil. If the only mutation is the initial declaration, it's dead.

### 2. Button/Action Handlers

```bash
# Find all Button actions
grep -rn 'Button(' Sources/ --include='*.swift' | grep -v 'Preview\|#Preview'

# Find all onTapGesture handlers
grep -rn '\.onTapGesture' Sources/ --include='*.swift'
```

For each button, check: is the button's parent view actually rendered? Is it inside an `if` guard that's never true?

### 3. NavigationLink Destinations

```bash
grep -rn 'NavigationLink(' Sources/ --include='*.swift' | grep -v 'Preview\|#Preview'
grep -rn '\.navigationDestination(' Sources/ --include='*.swift'
```

Verify each link's parent view is in the navigation hierarchy and the destination view exists.

### 4. Context Menus

```bash
grep -rn '\.contextMenu' Sources/ --include='*.swift'
```

Context menus are only available via long-press (iOS) or right-click (macOS). If the parent view isn't rendered, the menu is dead.

### 5. Toolbar Items

```bash
grep -rn 'ToolbarItem(' Sources/ --include='*.swift'
grep -rn '\.toolbar' Sources/ --include='*.swift'
```

Toolbar items are visible only when their parent view is the active navigation destination. Verify the view is reachable.

### 6. Notification Observer ↔ Poster Pairs

```bash
# Find all observers
grep -rn '\.onReceive\|addObserver' Sources/ --include='*.swift'

# Find all posters
grep -rn '\.post(name:' Sources/ --include='*.swift'
```

Every observer should have at least one poster, and vice versa. Unmatched observers are dead; unmatched posters are wasted work.

### 7. Orphan Views

```bash
# List all View structs
grep -rn 'struct.*: View' Sources/ --include='*.swift' | grep -v 'Preview\|#Preview'
```

For each View struct, check if it's instantiated anywhere outside its own file:

```bash
# For each view name, check for external references
grep -rn 'ViewName(' Sources/ --include='*.swift' | grep -v 'ViewName.swift'
```

If a View struct has zero external instantiations, it's an orphan. Check git history to confirm it's not newly created (pending integration).

### 8. Orphaned @State Variables

```bash
# Find @State vars that might only appear in their declaration
grep -rn '@State private var' Sources/ --include='*.swift' | while IFS=: read -r file line content; do
  var=$(echo "$content" | grep -oE 'var [a-zA-Z]+' | head -1 | cut -d' ' -f2)
  if [ -n "$var" ]; then
    count=$(grep -c "$var" "$file" 2>/dev/null)
    if [ "$count" -le 2 ]; then
      echo "⚠️  $file:$line — $var (only $count refs)"
    fi
  fi
done
```

A `@State` variable with ≤2 references (declaration + one read OR one write, but not both) is likely dead.

## Output Format

For each finding, report:

| Element | File:Line | Status | Notes |
|---------|-----------|--------|-------|
| `showDashboard` sheet | ContentView.swift:50 | ❌ Dead | Never set to true; dashboard moved to sidebar |
| `inferenceErrorBanner()` | ConversationAreaView.swift:257 | ❌ Dead | Function exists but never called |
| `ModelStripView` | ModelStripView.swift:1 | ❌ Orphan | Zero external instantiations |
| `BenchmarkSummaryCard` | iOSModelDetailView.swift:107 | ✅ Live | Rendered when `isActiveModel && metrics != nil` |
| `toggleCanvasRequested` | ContentView.swift:223 | ⚠️ Partial | Observer exists, poster exists, but handler only closes (never reopens) |

## After Fixing

After removing dead wires:
1. Run `tuist generate` if files were deleted
2. Build both platforms: `xcodebuild build` for macOS and iOS
3. Verify no new warnings from removed code
4. Commit with descriptive message listing each dead wire removed
