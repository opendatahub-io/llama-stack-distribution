# Testing GitHub Actions with `act`

This guide explains how to test GitHub Actions workflows locally using [`act`](https://github.com/nektos/act), a tool that runs your workflows locally using Podman (or Docker).

## What is `act`?

`act` is a CLI tool that allows you to run GitHub Actions workflows locally. It uses Podman (or Docker) to simulate the GitHub Actions runner environment, making it easier to test and debug workflows before pushing to GitHub.

**Note**: While GitHub Actions uses Docker, this guide uses Podman for local testing as it's rootless and better suited for local development environments.

## Installation

### Linux/macOS

```bash
# Using Homebrew (macOS/Linux)
brew install act

# Using curl
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Using Go
go install github.com/nektos/act@latest
```

### Verify Installation

```bash
act --version
```

## Prerequisites

- **Podman** (recommended for local testing) or **Docker** (fallback)
- **Git** (for cloning repositories)
- **Python 3.12+** (for running tests)

**Note**: GitHub Actions workflows use Docker, but for local testing with `act`, Podman is recommended as it's rootless and works better in local environments.

## Quick Start

### 1. Install `act`

```bash
# macOS/Linux with Homebrew
brew install act

# Or using curl
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

### 1.5. Ensure Podman is Available (Recommended)

```bash
# Check if Podman is installed
podman --version

# If not installed (Fedora/RHEL):
sudo dnf install podman

# Verify Podman is working
podman ps
```

**Note**: The helper script (`scripts/test-with-act.sh`) will automatically detect and use Podman if available, falling back to Docker if needed. GitHub Actions workflows use Docker, but Podman is preferred for local testing.

### 1.6. Setup Podman for Pre-commit Hooks

The shellcheck pre-commit hook requires Docker. To use Podman instead:

**Option 1: Install podman-docker (Recommended - Cleanest Solution)**

```bash
# Install podman-docker package (provides docker command that uses Podman)
sudo dnf install podman-docker  # Fedora/RHEL
# or
sudo apt install podman-docker  # Debian/Ubuntu

# Enable and start Podman socket
systemctl --user enable --now podman.socket

# Verify it works
docker --version  # Should show podman version
```

**Option 2: Use Podman Socket with DOCKER_HOST**

```bash
# Enable Podman socket service
systemctl --user enable --now podman.socket

# Set DOCKER_HOST to use Podman socket
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock

# Add to your ~/.bashrc or ~/.zshrc to make it permanent
echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock' >> ~/.bashrc
```

**Note**: Option 1 is cleaner as it provides a proper `docker` command without wrappers or environment variables.

### 1.7. Fix SELinux Context (Fedora/RHEL Only)

If you're on Fedora/RHEL with SELinux enabled and get permission denied errors from shellcheck:

```bash
# Run the fix script (requires sudo)
./scripts/fix-selinux-context.sh

# Or manually fix the context
sudo chcon -R -t user_home_t scripts/ tests/ distribution/entrypoint.sh
```

This fixes the SELinux context so containers can read the files.

### 2. Set Up Secrets

```bash
# Copy the example secrets file
cp .secrets.example .secrets

# Edit with your credentials
nano .secrets  # or use your preferred editor

# Ensure it's in .gitignore (should already be there)
echo ".secrets" >> .gitignore
```

### 3. Test a Workflow

**Option A: Use the helper script (easiest)**
```bash
./scripts/test-with-act.sh
```

**Option B: Use act directly**
```bash
# List available workflows
act -l

# Test main workflow (build only)
act workflow_dispatch \
  -W .github/workflows/redhat-distro-container.yml \
  --input llama_stack_commit_sha=main \
  --secret-file .secrets
```

## Basic Usage

### List Available Workflows

```bash
# List all workflows
act -l

# List workflows for a specific event
act pull_request -l
act workflow_dispatch -l
```

### Run a Workflow

```bash
# Run workflow for a specific event
act pull_request
act push
act workflow_dispatch

# Run a specific workflow file
act -W .github/workflows/redhat-distro-container.yml

# Run a specific job
act -j build-test-push
```

## Testing Your Workflows

### 1. Testing `redhat-distro-container.yml`

#### Basic Test (Build Only)

```bash
# Test the workflow_dispatch event (builds image, skips tests)
act workflow_dispatch \
  -W .github/workflows/redhat-distro-container.yml \
  --input llama_stack_commit_sha=main
```

#### Test with Pull Request Event

```bash
# Simulate a pull request
act pull_request \
  -W .github/workflows/redhat-distro-container.yml \
  --eventpath .github/workflows/pull_request.json
```

#### Create Event File for Testing

Create `.github/workflows/pull_request.json`:

```json
{
  "pull_request": {
    "number": 123,
    "head": {
      "sha": "abc123"
    },
    "base": {
      "ref": "main"
    }
  }
}
```

Then run:
```bash
act pull_request \
  -W .github/workflows/redhat-distro-container.yml \
  --eventpath .github/workflows/pull_request.json
```

### 2. Testing `live-tests.yml`

```bash
# Run live tests workflow
act workflow_dispatch \
  -W .github/workflows/live-tests.yml
```

## Handling Secrets

### Method 1: Using `.secrets` File (Recommended)

Create a `.secrets` file in your repository root:

```bash
# .secrets
QUAY_USERNAME=your-quay-username
QUAY_PASSWORD=your-quay-password
VERTEX_AI_PROJECT=your-gcp-project
VERTEX_AI_LOCATION=us-central1
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/123456789/locations/global/workloadIdentityPools/pool/providers/provider
GCP_SERVICE_ACCOUNT=service-account@project.iam.gserviceaccount.com
```

**Important**: Add `.secrets` to `.gitignore` to avoid committing secrets!

```bash
echo ".secrets" >> .gitignore
```

Then run `act` with the secrets file:

```bash
act workflow_dispatch --secret-file .secrets
```

### Method 2: Using Environment Variables

```bash
# Export secrets as environment variables
export QUAY_USERNAME=your-username
export QUAY_PASSWORD=your-password
export VERTEX_AI_PROJECT=your-project

# Run act (secrets are automatically available)
act workflow_dispatch
```

### Method 3: Using `--secret` Flag

```bash
act workflow_dispatch \
  --secret QUAY_USERNAME=your-username \
  --secret QUAY_PASSWORD=your-password \
  --secret VERTEX_AI_PROJECT=your-project
```

## Common `act` Options

### Specify Runner Image

```bash
# Use a specific runner image
act -P ubuntu-latest=catthehacker/ubuntu:act-latest

# Use a custom image
act -P ubuntu-latest=your-custom-image:tag
```

### Dry Run (List Steps)

```bash
# See what would run without executing
act --dry-run
act --list
```

### Verbose Output

```bash
# More detailed output
act -v
act -vv  # Even more verbose
```

### Run Specific Job

```bash
# Run only a specific job
act -j build-test-push
act -j live-tests
```

### Bind Mounts (for Local Files)

```bash
# Mount local directories
act --bind
```

## Example Commands

### Test Main Workflow - Build Only

```bash
act workflow_dispatch \
  -W .github/workflows/redhat-distro-container.yml \
  --input llama_stack_commit_sha=main \
  --secret-file .secrets \
  -j build-test-push
```

### Test Main Workflow - Full Test (PR Event)

```bash
# Create event file first
cat > .github/workflows/test-pr.json <<EOF
{
  "pull_request": {
    "number": 1,
    "head": {
      "sha": "$(git rev-parse HEAD)"
    },
    "base": {
      "ref": "main"
    }
  }
}
EOF

# Run workflow
act pull_request \
  -W .github/workflows/redhat-distro-container.yml \
  --eventpath .github/workflows/test-pr.json \
  --secret-file .secrets
```

### Test Live Tests Workflow

```bash
act workflow_dispatch \
  -W .github/workflows/live-tests.yml \
  --secret-file .secrets \
  -j live-tests
```

## Limitations and Workarounds

### 1. Container-in-Container (DinD)

Some workflows need Docker-in-Docker. `act` uses Podman/Docker, but nested containers can be tricky.

**Workaround with Podman**: Use host Podman socket:

```bash
# Start Podman socket service
podman system service --time=0 unix:///tmp/podman.sock &

# Use Podman socket
export DOCKER_HOST=unix:///tmp/podman.sock
act --container-options "-v /run/podman/podman.sock:/var/run/docker.sock"
```

**Workaround with Docker**: Use host Docker socket:

```bash
act --container-options "-v /var/run/docker.sock:/var/run/docker.sock"
```

### 2. Self-Hosted Actions

Actions in `.github/actions/` need to be available. `act` should handle this automatically.

**Workaround**: If issues occur, ensure the action files are present:

```bash
ls -la .github/actions/setup-vllm/
```

### 3. Matrix Strategies

Matrix strategies work, but you can test a single matrix entry:

```bash
# Test specific platform
act -j build-test-push --matrix platform:linux/amd64
```

### 4. OIDC Authentication

OIDC authentication (used in `live-tests.yml`) won't work locally. You'll need to:

- Skip authentication steps, or
- Use service account keys instead, or
- Mock the authentication

**Workaround for Live Tests**:

Modify the workflow temporarily or use a local test script instead:

```bash
# Use the local script instead
./scripts/run-live-tests-local.sh
```

### 5. GitHub API Calls

Some steps make GitHub API calls (like creating PRs). These won't work locally.

**Workaround**: These steps will fail, but you can test the rest of the workflow.

## Testing Strategy

### Step 1: Test Locally with `act` (Quick Feedback)

```bash
# Quick test - build only
act workflow_dispatch \
  -W .github/workflows/redhat-distro-container.yml \
  --input llama_stack_commit_sha=main \
  --dry-run  # First, see what would run
```

### Step 2: Test Specific Jobs

```bash
# Test just the build step
act -j build-test-push --dry-run

# Test with actual execution (may take time)
act -j build-test-push --secret-file .secrets
```

### Step 3: Test Full Workflow (if possible)

```bash
# Full workflow test (may have limitations)
act pull_request \
  -W .github/workflows/redhat-distro-container.yml \
  --eventpath .github/workflows/test-pr.json \
  --secret-file .secrets
```

### Step 4: Test on GitHub (Final Verification)

After local testing, push to GitHub and verify in the Actions tab.

## Troubleshooting

### Issue: "Cannot connect to Docker daemon"

**Solution with Podman**:
```bash
# Ensure Podman is running
podman ps

# Start Podman socket service for Docker-compatible API
podman system service --time=0 unix:///tmp/podman.sock &

# Set DOCKER_HOST for act
export DOCKER_HOST=unix:///tmp/podman.sock
```

**Solution with Docker**:
```bash
# Ensure Docker is running
docker ps

# If using Docker, ensure the daemon is started
sudo systemctl start docker  # Linux
```

### Issue: "Action not found"

**Solution**: Ensure action files exist:
```bash
ls -la .github/actions/
```

### Issue: "Secret not found"

**Solution**: Check your `.secrets` file:
```bash
cat .secrets
act --secret-file .secrets --list
```

### Issue: "Workflow not triggered"

**Solution**: Check the event type:
```bash
# List available events
act -l

# Use correct event
act workflow_dispatch  # Not act push
```

### Issue: "Permission denied"

**Solution**: Some permissions require GitHub context:
```bash
# Some steps may fail - this is expected for local testing
# Focus on testing the parts that work locally
```

## Quick Reference

### Most Common Commands

```bash
# List workflows
act -l

# Test main workflow (build)
act workflow_dispatch \
  -W .github/workflows/redhat-distro-container.yml \
  --input llama_stack_commit_sha=main \
  --secret-file .secrets

# Test live tests workflow
act workflow_dispatch \
  -W .github/workflows/live-tests.yml \
  --secret-file .secrets

# Dry run (see what would execute)
act --dry-run -l

# Verbose output
act -vv workflow_dispatch
```

### Create `.secrets` File Template

```bash
cat > .secrets <<EOF
# Quay.io (for publishing)
QUAY_USERNAME=
QUAY_PASSWORD=

# Vertex AI (for live tests)
VERTEX_AI_PROJECT=
VERTEX_AI_LOCATION=us-central1
GCP_WORKLOAD_IDENTITY_PROVIDER=
GCP_SERVICE_ACCOUNT=
EOF

chmod 600 .secrets
echo ".secrets" >> .gitignore
```

## Best Practices

1. **Always use `.secrets` file** - Never commit secrets
2. **Start with `--dry-run`** - See what would execute first
3. **Test one job at a time** - Use `-j` to isolate issues
4. **Use verbose mode** - `-vv` for debugging
5. **Test incrementally** - Test build first, then tests
6. **Know the limitations** - Some steps won't work locally (OIDC, GitHub API)

## Next Steps

1. Install `act`: `brew install act` or `curl ... | sudo bash`
2. Create `.secrets` file with your credentials
3. Test with `--dry-run` first
4. Run actual workflow: `act workflow_dispatch --secret-file .secrets`
5. Fix any issues locally
6. Push to GitHub for final verification

## Additional Resources

- [act Documentation](https://github.com/nektos/act)
- [act Examples](https://github.com/nektos/act-examples)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
