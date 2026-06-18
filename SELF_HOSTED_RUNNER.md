<!-- Copyright 2026 Andrew Voirol

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. -->

# Self-Hosted Runner Setup Guide

This guide covers setting up a macOS machine as a GitHub Actions self-hosted runner for Edge AI Lab. Self-hosted runners are required for jobs that need Apple Silicon GPU access and pre-staged model files — specifically the `self-hosted-benchmark` and `eval-pipeline` jobs in `benchmark.yml`.

---

## Prerequisites

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| macOS | 26.0+ (Tahoe) | Latest stable |
| Chip | Apple Silicon (M1) | M2 Pro / M4 or later |
| RAM | 16 GB | 32 GB+ |
| Disk Space | 50 GB free | 100 GB+ free |
| Xcode | 26.0+ | Latest stable |
| GitHub Access | Repository admin | Repository admin |

You also need:
- **Command Line Tools** installed (`xcode-select --install`)
- **Git** (bundled with CLT)
- A stable **internet connection** for communicating with the GitHub Actions service

---

## Runner Installation

### 1. Download the Runner

Navigate to the repository on GitHub:

**Settings → Actions → Runners → New self-hosted runner**

Select **macOS** and **ARM64** (Apple Silicon). Follow the download instructions, or run:

```bash
# Create a directory for the runner
mkdir ~/actions-runner && cd ~/actions-runner

# Download the latest runner package (check GitHub for current version)
curl -o actions-runner-osx-arm64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.325.0/actions-runner-osx-arm64-2.325.0.tar.gz

# Extract
tar xzf actions-runner-osx-arm64.tar.gz
```

### 2. Configure the Runner

```bash
./config.sh \
  --url https://github.com/AndrewVoirol/edge-ai-lab \
  --token <TOKEN> \
  --labels apple-silicon \
  --name "edge-ai-lab-$(hostname -s)"
```

> **Note**: The `<TOKEN>` is a one-time registration token generated from the GitHub UI (Settings → Actions → Runners → New self-hosted runner). It expires after 1 hour.

### 3. Start the Runner

**For testing** (foreground, Ctrl+C to stop):

```bash
./run.sh
```

**For production** (launchd service, survives reboots):

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

Service management commands:

```bash
sudo ./svc.sh status    # Check if running
sudo ./svc.sh stop      # Stop the service
sudo ./svc.sh uninstall # Remove the service
```

---

## Runner Labels

The `benchmark.yml` workflow targets self-hosted runners using:

```yaml
runs-on: [self-hosted, apple-silicon]
```

Your runner **must** have both labels to pick up these jobs:

| Label | Purpose |
|-------|---------|
| `self-hosted` | Automatically applied by GitHub for all self-hosted runners |
| `apple-silicon` | Applied during `./config.sh --labels apple-silicon` |

You can verify labels in **Settings → Actions → Runners** — click your runner name to see assigned labels.

---

## Model Pre-Staging

The self-hosted benchmark job auto-discovers `.litertlm` model files from standard locations. You must pre-stage at least one model on the runner machine.

### 1. Create the Models Directory

```bash
mkdir -p ~/models
```

### 2. Download Models

Download from [HuggingFace](https://huggingface.co/litert-community):

```bash
# Example: Gemma 4 E2B IT
huggingface-cli download litert-community/gemma-4-e2b-it-litertlm \
  --local-dir ~/models/

# Or copy from project directory if available
cp /path/to/gemma-edgegallery/models/*.litertlm ~/models/
```

### 3. Expected File Names

| Model | File Name |
|-------|-----------|
| Gemma 4 E2B IT | `gemma-4-e2b-it.litertlm` |
| Gemma 4 E4B IT (Web) | `gemma-4-e4b-it-web.litertlm` |

### 4. Model Discovery

The `self-hosted-benchmark` job in `benchmark.yml` searches for models in this order:

1. `~/models/` — primary location
2. `~/Antigravity/Projects/gemma-edgegallery/models/` — fallback

The first `.litertlm` file found is used for benchmarking. To override auto-discovery, set the `PERFORMANCE_TEST_MODEL_PATH` environment variable:

```bash
export PERFORMANCE_TEST_MODEL_PATH="$HOME/models/gemma-4-e2b-it.litertlm"
```

### 5. Verify Models

```bash
ls -lh ~/models/*.litertlm
# Expected output: one or more .litertlm files
```

---

## Tuist Setup

Edge AI Lab uses [Tuist](https://tuist.dev) (managed via [mise](https://mise.run)) to generate Xcode project files. The runner needs this configured before builds.

### 1. Install mise

```bash
curl https://mise.run | sh
```

Add to your shell profile (if not already):

```bash
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc
source ~/.zshrc
```

### 2. Install Tuist

```bash
# From the project root — version is pinned in .mise.toml
cd ~/Antigravity/Projects/gemma-edgegallery
mise install tuist
```

### 3. Generate Project Files

```bash
tuist generate
```

This creates `EdgeAILab.xcworkspace` and all `.xcodeproj` files needed for `xcodebuild`.

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PERFORMANCE_TEST_MODEL_PATH` | No | Auto-discovered | Absolute path to a `.litertlm` model file |
| `CODECOV_TOKEN` | No | — | Token for uploading code coverage reports |
| `DEVELOPMENT_TEAM` | No | `Y7J7WUK693` | Apple Developer Team ID for code signing |

### Setting Variables

**Runner-level** (in `~/actions-runner/.env`):

```bash
echo "PERFORMANCE_TEST_MODEL_PATH=/Users/github-runner/models/gemma-4-e2b-it.litertlm" >> ~/actions-runner/.env
echo "CODECOV_TOKEN=your-token-here" >> ~/actions-runner/.env
```

**Repository secrets** (preferred for sensitive values):

Settings → Secrets and variables → Actions → New repository secret

> **Tip**: Use repository secrets for `CODECOV_TOKEN` and runner-level `.env` for `PERFORMANCE_TEST_MODEL_PATH` (since it's machine-specific).

---

## Security Hardening

### Create a Dedicated User

```bash
# Create a non-admin user for the runner
sudo dscl . -create /Users/github-runner
sudo dscl . -create /Users/github-runner UserShell /bin/zsh
sudo dscl . -create /Users/github-runner RealName "GitHub Runner"
sudo dscl . -create /Users/github-runner UniqueID 550
sudo dscl . -create /Users/github-runner PrimaryGroupID 20
sudo dscl . -create /Users/github-runner NFSHomeDirectory /Users/github-runner
sudo mkdir -p /Users/github-runner
sudo chown github-runner:staff /Users/github-runner
```

### Security Checklist

| Practice | Details |
|----------|---------|
| **Don't run as root** | Install and run the runner service as a non-admin user |
| **Restrict network access** | If possible, limit outbound access to GitHub API endpoints (`github.com`, `api.github.com`, `*.actions.githubusercontent.com`) |
| **Rotate tokens** | Re-register the runner periodically with a fresh token via `./config.sh remove` and re-configure |
| **Ephemeral runners** | Use `--ephemeral` flag during `./config.sh` for one-shot runners that de-register after each job |
| **No production secrets** | Never store production API keys, signing certificates, or user data on the runner |
| **Audit workflows** | Only allow trusted workflows to run on self-hosted runners (restrict fork PRs) |

### Ephemeral Mode

For maximum isolation, configure the runner as ephemeral — it processes one job and then de-registers:

```bash
./config.sh \
  --url https://github.com/AndrewVoirol/edge-ai-lab \
  --token <TOKEN> \
  --labels apple-silicon \
  --name "edge-ai-lab-$(hostname -s)" \
  --ephemeral
```

> **Note**: Ephemeral runners require re-registration after every job. This is best paired with an orchestration script or a launchd plist that re-configures automatically.

---

## Verification

### 1. Local Test Run

Run the CI test script to verify the runner can build and test:

```bash
./automation/ci_test_runner.sh --macOS --skip-integration --skip-performance
```

### 2. Trigger a Workflow

From the GitHub UI:

1. Go to **Actions → Benchmark → Run workflow**
2. Leave `model_path` empty (triggers `self-hosted-benchmark` job)
3. Click **Run workflow**

### 3. Check Runner Status

Navigate to **Settings → Actions → Runners**. Your runner should appear with a **green** ● status indicator and the labels `self-hosted` and `apple-silicon`.

### 4. Verify Model Discovery

```bash
# Simulate what the workflow does
MODEL_DIR="${HOME}/models"
find "$MODEL_DIR" -name "*.litertlm" -type f 2>/dev/null
```

---

## Troubleshooting

### SPM Cache Corruption

**Symptom**: Build fails with "manifest parse error" or stale dependency references.

```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf .build
tuist generate
```

### Xcode Version Mismatch

**Symptom**: Build fails with SDK/toolchain errors.

```bash
# Point to the correct Xcode installation
sudo xcode-select -s /Applications/Xcode.app

# Verify
xcodebuild -version
```

### Code Signing Errors

**Symptom**: `Code signing is required` or `No signing certificate` errors.

CI workflows build with code signing disabled:

```bash
xcodebuild build \
  -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

### Model Not Found

**Symptom**: `⚠️ No pre-staged models found — skipping inference benchmark`

```bash
# Verify models directory exists and contains .litertlm files
ls -lh ~/models/*.litertlm

# If empty, download or copy models
mkdir -p ~/models
cp /path/to/your/models/*.litertlm ~/models/
```

### Runner Offline

**Symptom**: Runner shows grey ● or "Offline" in GitHub Settings.

```bash
# Check service status
sudo ./svc.sh status

# Review diagnostic logs
ls ~/actions-runner/_diag/
tail -100 ~/actions-runner/_diag/Runner_*.log

# Restart the service
sudo ./svc.sh stop
sudo ./svc.sh start
```

### Tuist Generate Fails

**Symptom**: `tuist: command not found` or generate errors.

```bash
# Re-install mise and tuist
curl https://mise.run | sh
eval "$(~/.local/bin/mise activate zsh)"
mise install tuist

# Re-generate
tuist generate
```

---

## Quick Reference Commands

```bash
# ── Runner Management ──────────────────────────────────────
./run.sh                                   # Start runner (foreground)
sudo ./svc.sh install && sudo ./svc.sh start  # Install as service
sudo ./svc.sh status                       # Check service status
sudo ./svc.sh stop                         # Stop service
sudo ./svc.sh uninstall                    # Remove service
./config.sh remove                         # De-register runner

# ── Project Setup ──────────────────────────────────────────
curl https://mise.run | sh                 # Install mise
mise install tuist                         # Install tuist
tuist generate                             # Generate Xcode project

# ── Testing ────────────────────────────────────────────────
./automation/ci_test_runner.sh --macOS --skip-integration --skip-performance
xcodebuild test \
  -workspace EdgeAILab.xcworkspace \
  -scheme "Edge AI Lab" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# ── Model Management ──────────────────────────────────────
mkdir -p ~/models                          # Create models directory
ls ~/models/*.litertlm                     # Verify models
find ~/models -name "*.litertlm" -type f   # Discover models

# ── Troubleshooting ───────────────────────────────────────
rm -rf ~/Library/Caches/org.swift.swiftpm  # Clear SPM cache
rm -rf .build                              # Clear build artifacts
sudo xcode-select -s /Applications/Xcode.app  # Fix Xcode selection
tail -100 ~/actions-runner/_diag/Runner_*.log  # View runner logs
```
