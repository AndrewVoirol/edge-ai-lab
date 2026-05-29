#!/bin/bash
# Check model availability for performance tests
# Usage: .antigravity/skills/performance-testing/scripts/provision-model.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../../.." && cd .. && pwd)"
MODELS_DIR="$PROJECT_ROOT/models"

echo "🔍 Checking model availability..."
echo "   Models directory: $MODELS_DIR"
echo ""

if [ ! -d "$MODELS_DIR" ]; then
    echo "❌ Models directory does not exist: $MODELS_DIR"
    echo "   Create it with: mkdir -p $MODELS_DIR"
    echo "   Then copy your .litertlm model file(s) into it."
    exit 1
fi

# Find all .litertlm files
MODELS=($(find "$MODELS_DIR" -name "*.litertlm" -maxdepth 1 2>/dev/null))

if [ ${#MODELS[@]} -eq 0 ]; then
    echo "⚠️  No .litertlm model files found in $MODELS_DIR"
    echo ""
    echo "   To run performance tests, copy a model file:"
    echo "   cp /path/to/your-model.litertlm $MODELS_DIR/"
    echo ""
    echo "   Unit tests will still work without a model."
    exit 1
fi

echo "✅ Found ${#MODELS[@]} model(s):"
for model in "${MODELS[@]}"; do
    SIZE=$(du -h "$model" | cut -f1)
    echo "   📦 $(basename "$model") ($SIZE)"
done
echo ""
echo "✅ Performance tests can run."
