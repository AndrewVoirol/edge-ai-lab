---
name: plan-compliance-audit
description: Systematic verification of implementation plan completion. Use when declaring a plan complete, when the user asks for a status check, or before creating a walkthrough/summary artifact.
---

# Plan Compliance Audit

When you need to verify that an implementation plan has been fully executed, follow this process BEFORE declaring completion.

## Step 1: Extract Every Deliverable

Read the implementation plan line by line. For each section, extract:
- Every file mentioned by name (e.g., `Tests/Integration/FooTests.swift`)
- Every quantitative target (e.g., "30 prompts", "≥80% coverage")
- Every process step (e.g., "run controlled eval on device")
- Every artifact to produce (e.g., "coverage gap analysis")

Create a checklist of these items.

## Step 2: Verify Each Deliverable Exists

For each item on the checklist:
- **Files**: Verify the file exists at the specified path with `view_file` or `list_dir`
- **Quantitative targets**: Run the measurement (e.g., count prompts, run coverage)
- **Process steps**: Check for evidence they were executed (e.g., updated baselines with timestamps)
- **Artifacts**: Verify they exist and contain the specified content

## Step 3: Check for Deviations

Compare what was delivered vs. what was planned:
- Were any items renamed? (e.g., "4B: Flow viewer" → "4B: Coverage measurement")
- Were any items folded into other items without documenting the merge?
- Were any items simply never started?
- Were estimated values used where measured values were required?

## Step 4: Report Honestly

Create a table with columns: Plan Item | Status | Evidence | Notes

Use these statuses:
- ✅ DONE — delivered as specified
- ⚠️ PARTIAL — delivered but not matching spec
- 🔄 CHANGED — scope changed without flagging
- ❌ NOT DONE — never executed
- ⏭️ DEFERRED — explicitly deferred with rationale documented

**Never use ✅ for items that are PARTIAL, CHANGED, or DEFERRED.**

## When to Use This Skill

- Before writing a walkthrough artifact
- Before telling the user a plan is "100% complete"
- When the user asks "is this aligned with the plan?"
- After subagents report task completion (spot-check their claims)
