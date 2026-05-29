#!/bin/bash
# Tuist project generation wrapper with error handling
# Usage: .antigravity/skills/tuist/scripts/generate.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../../.." && cd .. && pwd)"
cd "$PROJECT_ROOT"

echo "🔄 Running tuist generate..."

# Check if tuist is installed
if ! command -v tuist &> /dev/null; then
    echo "❌ Error: tuist is not installed. Install via: brew install tuist"
    exit 1
fi

# Check if Project.swift exists
if [ ! -f "Project.swift" ]; then
    echo "❌ Error: Project.swift not found in $PROJECT_ROOT"
    exit 1
fi

# Run tuist generate
if tuist generate 2>&1; then
    echo "✅ Project generated successfully"
    
    # Verify workspace was created
    if [ -d "GemmaEdgeGallery.xcworkspace" ]; then
        echo "✅ Workspace: GemmaEdgeGallery.xcworkspace"
    else
        echo "⚠️  Warning: Workspace not found after generation"
    fi
else
    echo "❌ tuist generate failed"
    exit 1
fi
