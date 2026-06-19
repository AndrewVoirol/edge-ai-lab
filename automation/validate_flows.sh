#!/usr/bin/env bash
# validate_flows.sh — Validate all automation flow JSON files
#
# Checks:
#   1. JSON syntax (via python3 -m json.tool)
#   2. Required top-level fields: name, description, platform, steps
#   3. Required step fields: step, action, description
#   4. Step numbering (sequential, starting at 1)
#   5. Known action types
#
# Usage:
#   ./automation/validate_flows.sh              # from project root
#   ./automation/validate_flows.sh --verbose    # show each file as it's checked
#
# Exit codes:
#   0 — all flows valid
#   1 — one or more validation failures

set -uo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWS_DIR="${SCRIPT_DIR}/flows"

VERBOSE=false
if [[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]]; then
    VERBOSE=true
fi

# Known action types (union of macOS + iOS runners)
KNOWN_ACTIONS=(
    "verify_ui"
    "tap"
    "type_text"
    "wait"
    "keyboard_shortcut"
    "scroll_to"
    "navigate_tab"
    "open_sheet"
    "dismiss_sheet"
    "verify_not_exists"
    "verify_enabled"
    "verify_value"
    "tap_first_match"
    "tap_if_exists"
    "screenshot"
)

# ── Counters ─────────────────────────────────────────────────────────────────
total=0
passed=0
failed=0
warnings=0
errors=()

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Helpers ──────────────────────────────────────────────────────────────────
log_pass() { echo -e "  ${GREEN}✓${NC} $1"; }
log_fail() { echo -e "  ${RED}✗${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

# ── Find all flow JSON files ────────────────────────────────────────────────
if [[ ! -d "${FLOWS_DIR}" ]]; then
    echo -e "${RED}Error:${NC} Flows directory not found: ${FLOWS_DIR}"
    exit 1
fi

FLOW_FILES=()
while IFS= read -r -d '' file; do
    FLOW_FILES+=("$file")
done < <(find "${FLOWS_DIR}" -name "*.json" -type f -print0 | sort -z)

if [[ ${#FLOW_FILES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}Warning:${NC} No .json files found in ${FLOWS_DIR}"
    exit 0
fi

echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       Flow JSON Validation Report                   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Scanning: ${CYAN}${FLOWS_DIR}${NC}"
echo -e "Found:    ${BOLD}${#FLOW_FILES[@]}${NC} flow files"
echo ""

# ── Validate each flow ──────────────────────────────────────────────────────
for flow_file in "${FLOW_FILES[@]}"; do
    total=$((total + 1))
    relative_path="${flow_file#"${SCRIPT_DIR}/"}"
    file_valid=true

    echo -e "${BOLD}─── ${relative_path} ───${NC}"

    # 1. JSON syntax validation
    if ! python3 -m json.tool "${flow_file}" > /dev/null 2>&1; then
        log_fail "JSON syntax error"
        errors+=("${relative_path}: JSON syntax error")
        file_valid=false
        failed=$((failed + 1))
        echo ""
        continue
    fi
    $VERBOSE && log_pass "JSON syntax valid"

    # 2. Required top-level fields
    for field in name description steps; do
        has_field=$(python3 -c "
import json, sys
with open('${flow_file}') as f:
    data = json.load(f)
print('yes' if '${field}' in data else 'no')
" 2>/dev/null)
        if [[ "${has_field}" != "yes" ]]; then
            log_fail "Missing required field: ${field}"
            errors+=("${relative_path}: missing '${field}'")
            file_valid=false
        fi
    done

    # Check platform (recommended but not strictly required)
    has_platform=$(python3 -c "
import json, sys
with open('${flow_file}') as f:
    data = json.load(f)
print('yes' if 'platform' in data else 'no')
" 2>/dev/null)
    if [[ "${has_platform}" != "yes" ]]; then
        log_warn "Missing recommended field: platform"
        warnings=$((warnings + 1))
    fi

    # 3. Validate steps array
    step_errors=$(python3 -c "
import json, sys

with open('${flow_file}') as f:
    data = json.load(f)

steps = data.get('steps', [])
if not isinstance(steps, list):
    print('ERROR: steps is not an array')
    sys.exit(0)

if len(steps) == 0:
    print('ERROR: steps array is empty')
    sys.exit(0)

known_actions = set(${KNOWN_ACTIONS[@]/#/\"}${KNOWN_ACTIONS[@]/%/\"})

errors = []
for i, step in enumerate(steps):
    prefix = f'Step {i+1}'

    # Required step fields
    if 'step' not in step:
        errors.append(f'{prefix}: missing \"step\" number')
    if 'action' not in step:
        errors.append(f'{prefix}: missing \"action\"')
    if 'description' not in step:
        errors.append(f'{prefix}: missing \"description\"')

    # Check step numbering
    if 'step' in step and step['step'] != i + 1:
        errors.append(f'{prefix}: step number is {step[\"step\"]}, expected {i+1}')

    # Check action is known
    action = step.get('action', '')
    known = [
        'verify_ui', 'tap', 'type_text', 'wait', 'keyboard_shortcut',
        'scroll_to', 'navigate_tab', 'open_sheet', 'dismiss_sheet',
        'verify_not_exists', 'verify_enabled', 'verify_value',
        'tap_first_match', 'tap_if_exists', 'screenshot'
    ]
    if action and action not in known:
        errors.append(f'{prefix}: unknown action \"{action}\"')

for e in errors:
    print(f'ERROR: {e}')
" 2>/dev/null)

    if [[ -n "${step_errors}" ]]; then
        while IFS= read -r err; do
            if [[ "${err}" == ERROR:* ]]; then
                log_fail "${err#ERROR: }"
                errors+=("${relative_path}: ${err#ERROR: }")
                file_valid=false
            fi
        done <<< "${step_errors}"
    fi

    # 4. Validate step-specific required fields
    field_errors=$(python3 -c "
import json, sys

with open('${flow_file}') as f:
    data = json.load(f)

steps = data.get('steps', [])
errors = []

for step in steps:
    num = step.get('step', '?')
    action = step.get('action', '')

    if action == 'tap' and 'target_element' not in step:
        errors.append(f'Step {num} (tap): missing target_element')
    elif action == 'type_text':
        if 'target_element' not in step:
            errors.append(f'Step {num} (type_text): missing target_element')
        if 'value' not in step:
            errors.append(f'Step {num} (type_text): missing value')
    elif action == 'keyboard_shortcut' and 'key' not in step:
        errors.append(f'Step {num} (keyboard_shortcut): missing key')
    elif action == 'scroll_to' and 'target_element' not in step:
        errors.append(f'Step {num} (scroll_to): missing target_element')
    elif action == 'verify_not_exists' and 'target_element' not in step:
        errors.append(f'Step {num} (verify_not_exists): missing target_element')
    elif action == 'verify_enabled' and 'target_element' not in step:
        errors.append(f'Step {num} (verify_enabled): missing target_element')
    elif action == 'verify_value':
        if 'target_element' not in step:
            errors.append(f'Step {num} (verify_value): missing target_element')
        if 'expected' not in step and 'value' not in step:
            errors.append(f'Step {num} (verify_value): missing expected or value')
    elif action == 'verify_ui':
        if 'expected_elements' not in step and 'expected_elements_any' not in step:
            errors.append(f'Step {num} (verify_ui): missing expected_elements or expected_elements_any')
    elif action == 'open_sheet' and 'target_element' not in step:
        errors.append(f'Step {num} (open_sheet): missing target_element')

for e in errors:
    print(f'ERROR: {e}')
" 2>/dev/null)

    if [[ -n "${field_errors}" ]]; then
        while IFS= read -r err; do
            if [[ "${err}" == ERROR:* ]]; then
                log_fail "${err#ERROR: }"
                errors+=("${relative_path}: ${err#ERROR: }")
                file_valid=false
            fi
        done <<< "${field_errors}"
    fi

    if $file_valid; then
        step_count=$(python3 -c "
import json
with open('${flow_file}') as f:
    print(len(json.load(f).get('steps', [])))
" 2>/dev/null)
        log_pass "Valid (${step_count} steps)"
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    echo ""
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}Summary${NC}"
echo -e "  Total:    ${total}"
echo -e "  ${GREEN}Passed:${NC}  ${passed}"
echo -e "  ${RED}Failed:${NC}  ${failed}"
echo -e "  ${YELLOW}Warnings:${NC} ${warnings}"
echo ""

if [[ ${failed} -gt 0 ]]; then
    echo -e "${RED}${BOLD}VALIDATION FAILED${NC}"
    echo ""
    echo "Errors:"
    for err in "${errors[@]}"; do
        echo -e "  ${RED}•${NC} ${err}"
    done
    exit 1
else
    echo -e "${GREEN}${BOLD}ALL FLOWS VALID ✓${NC}"
    exit 0
fi
