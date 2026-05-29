#!/bin/bash
# Verify both iOS and macOS targets build successfully
# Usage: .antigravity/skills/xcode-mcp/scripts/verify-build.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../../.." && cd .. && pwd)"
cd "$PROJECT_ROOT"

echo "🔨 Verifying builds..."
echo "==================="

# Build iOS Simulator
echo ""
echo "📱 Building iOS Simulator target..."
if xcodebuild build \
    -workspace GemmaEdgeGallery.xcworkspace \
    -scheme GemmaEdgeGallery_iOS \
    -destination "generic/platform=iOS Simulator" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet 2>&1; then
    echo "✅ iOS Simulator build: SUCCESS"
else
    echo "❌ iOS Simulator build: FAILED"
    exit 1
fi

# Build macOS
echo ""
echo "💻 Building macOS target..."
if xcodebuild build \
    -workspace GemmaEdgeGallery.xcworkspace \
    -scheme GemmaEdgeGallery_macOS \
    -destination "platform=macOS" \
    -quiet 2>&1; then
    echo "✅ macOS build: SUCCESS"
else
    echo "❌ macOS build: FAILED"
    exit 1
fi

echo ""
echo "==================="
echo "✅ All builds passed"
