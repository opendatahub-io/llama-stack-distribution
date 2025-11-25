#!/usr/bin/env bash
# Helper script to test GitHub Actions workflows with act
# Usage: ./scripts/test-with-act.sh [workflow] [event]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if act is installed
if ! command -v act &> /dev/null; then
    echo -e "${RED}Error: act is not installed${NC}"
    echo "Install it with: brew install act"
    echo "Or: curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash"
    exit 1
fi

# Check if Podman or Docker is available
USE_PODMAN=false
if command -v podman &> /dev/null; then
    if podman ps &> /dev/null; then
        USE_PODMAN=true
        echo -e "${GREEN}Using Podman for container runtime${NC}"
    else
        echo -e "${YELLOW}Podman is installed but not running. Trying to start...${NC}"
        # Try to start Podman service
        if podman system service --time=0 unix:///tmp/podman.sock &> /dev/null &; then
            sleep 1
            if podman ps &> /dev/null; then
                USE_PODMAN=true
                echo -e "${GREEN}Podman started successfully${NC}"
            fi
        fi
    fi
fi

# Fallback to Docker if Podman is not available or not working
if [ "$USE_PODMAN" = false ]; then
    if command -v docker &> /dev/null; then
        if docker ps &> /dev/null; then
            echo -e "${YELLOW}Using Docker for container runtime (consider using Podman for local testing)${NC}"
        else
            echo -e "${RED}Error: Docker is not running${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Error: Neither Podman nor Docker is available${NC}"
        echo "Install Podman (recommended): sudo dnf install podman  # Fedora/RHEL"
        echo "Or Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
fi

# Set up Podman Docker-compatible socket if using Podman
if [ "$USE_PODMAN" = true ]; then
    # Check if Podman socket service is already running
    PODMAN_SOCK="/run/user/$(id -u)/podman/podman.sock"
    if [ -S "$PODMAN_SOCK" ]; then
        # Use existing user socket
        export DOCKER_HOST="unix://$PODMAN_SOCK"
        echo -e "${GREEN}Using existing Podman socket: $PODMAN_SOCK${NC}"
    else
        # Try to use system socket or start service
        SYSTEM_SOCK="/run/podman/podman.sock"
        if [ -S "$SYSTEM_SOCK" ]; then
            export DOCKER_HOST="unix://$SYSTEM_SOCK"
            echo -e "${GREEN}Using system Podman socket: $SYSTEM_SOCK${NC}"
        else
            # Start Podman socket service in background
            echo -e "${YELLOW}Starting Podman socket service...${NC}"
            podman system service --time=0 unix:///tmp/podman.sock &> /dev/null &
            PODMAN_PID=$!
            sleep 2
            export DOCKER_HOST=unix:///tmp/podman.sock
            echo -e "${GREEN}Started Podman socket service (PID: $PODMAN_PID)${NC}"
        fi
    fi
fi

# Check for secrets file
SECRETS_FILE=".secrets"
if [ ! -f "$SECRETS_FILE" ]; then
    echo -e "${YELLOW}Warning: .secrets file not found${NC}"
    echo "Create one with: cat > .secrets <<EOF"
    echo "QUAY_USERNAME=your-username"
    echo "QUAY_PASSWORD=your-password"
    echo "VERTEX_AI_PROJECT=your-project"
    echo "EOF"
    echo ""
    read -p "Continue without secrets? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SECRETS_FLAG=""
else
    SECRETS_FLAG="--secret-file $SECRETS_FILE"
    echo -e "${GREEN}Using secrets from $SECRETS_FILE${NC}"
fi

# Determine workflow
WORKFLOW="${1:-}"
if [ -z "$WORKFLOW" ]; then
    echo "Available workflows:"
    echo "  1) redhat-distro-container.yml"
    echo "  2) live-tests.yml"
    echo ""
    read -p "Select workflow (1 or 2): " choice
    case $choice in
        1) WORKFLOW="redhat-distro-container.yml" ;;
        2) WORKFLOW="live-tests.yml" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

WORKFLOW_PATH=".github/workflows/$WORKFLOW"
if [ ! -f "$WORKFLOW_PATH" ]; then
    echo -e "${RED}Error: Workflow not found: $WORKFLOW_PATH${NC}"
    exit 1
fi

# Determine event
EVENT="${2:-workflow_dispatch}"
echo -e "${GREEN}Testing workflow: $WORKFLOW${NC}"
echo -e "${GREEN}Event: $EVENT${NC}"
echo ""

# Build act command
ACT_CMD="act $EVENT -W $WORKFLOW_PATH $SECRETS_FLAG"

# Add workflow-specific options
case "$WORKFLOW" in
    redhat-distro-container.yml)
        if [ "$EVENT" == "workflow_dispatch" ]; then
            ACT_CMD="$ACT_CMD --input llama_stack_commit_sha=main"
        fi
        ;;
    live-tests.yml)
        # No special inputs needed
        ;;
esac

# Ask for dry-run first
echo "Options:"
echo "  1) Dry run (list steps only)"
echo "  2) Full execution"
echo ""
read -p "Select option (1 or 2): " option
case $option in
    1) ACT_CMD="$ACT_CMD --dry-run" ;;
    2) ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

echo ""
echo -e "${YELLOW}Running: $ACT_CMD${NC}"
echo ""

# Execute
eval "$ACT_CMD"

