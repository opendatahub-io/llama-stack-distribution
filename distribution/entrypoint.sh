#!/bin/bash

# Unified entrypoint script for Llama Stack distribution
# Supports both full and standalone modes via STANDALONE environment variable

set -e

echo "=== Llama Stack Distribution Entrypoint ==="

# Check if we should run in standalone mode
if [ "${STANDALONE:-false}" = "true" ]; then
    echo "Running in STANDALONE mode (no Kubernetes dependencies)"
    
    # Use standalone configuration
    CONFIG_FILE="/opt/app-root/run-standalone.yaml"
    
    # Filter out TrustyAI providers from providers.d directory
    echo "Filtering out TrustyAI providers for standalone mode..."
    mkdir -p ${HOME}/.llama/providers.d
    
    # Copy only non-TrustyAI providers
    find /opt/app-root/.llama/providers.d -name "*.yaml" ! -name "*trustyai*" -exec cp {} ${HOME}/.llama/providers.d/ \; 2>/dev/null || true
    
    # Remove the external_providers_dir from the config to prevent loading TrustyAI providers
    echo "Disabling external providers directory for standalone mode..."
    sed -i 's|external_providers_dir:.*|# external_providers_dir: disabled for standalone mode|' "$CONFIG_FILE"
    
    echo "✓ Standalone configuration ready"
    echo "✓ TrustyAI providers excluded"
else
    echo "Running in FULL mode (with Kubernetes dependencies)"
    
    # Use full configuration
    CONFIG_FILE="/opt/app-root/run-full.yaml"
    
    # Copy all providers
    echo "Setting up all providers..."
    mkdir -p ${HOME}/.llama/providers.d
    cp -r /opt/app-root/.llama/providers.d/* ${HOME}/.llama/providers.d/ 2>/dev/null || true
    
    echo "✓ Full configuration ready"
    echo "✓ All providers available"
fi

echo "Configuration file: $CONFIG_FILE"
echo "APIs enabled: $(grep -A 20 '^apis:' $CONFIG_FILE | grep '^-' | wc -l) APIs"

# Show which APIs are available
echo "Available APIs:"
grep -A 20 '^apis:' $CONFIG_FILE | grep '^-' | sed 's/^- /  - /' || echo "  (none listed)"

# Start the server
echo "Starting Llama Stack server..."
exec python -m llama_stack.core.server.server "$CONFIG_FILE"
