#!/usr/bin/env bash
# Common utility functions for test scripts

function validate_model_parameter() {
    # Check if model is provided
    if [ -z "$1" ]; then
        echo "Error: No model provided"
        return 1
    fi
}
