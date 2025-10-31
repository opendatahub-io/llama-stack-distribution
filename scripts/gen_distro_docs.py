#!/usr/bin/env python3

import yaml
import re
from pathlib import Path


REPO_ROOT = Path(__file__).parent.parent


def extract_llama_stack_version():
    """Extract Llama Stack version from the Containerfile."""
    containerfile_path = REPO_ROOT / "distribution" / "Containerfile"

    if not containerfile_path.exists():
        print(f"Error: {containerfile_path} not found")
        exit(1)

    try:
        with open(containerfile_path, "r") as file:
            content = file.read()

        # Look for llama-stack version in pip install commands
        # Pattern matches: llama-stack==X.Y.Z or llama-stack==X.Y.ZrcN+rhaiM
        pattern = r"llama-stack==([0-9]+\.[0-9]+\.[0-9]+(?:rc[0-9]+)?(?:\+rhai[0-9]+)?)"
        match = re.search(pattern, content)

        if match:
            return match.group(1)

        # Look for git URL format: git+https://github.com/*/llama-stack.git@vVERSION or @VERSION
        git_pattern = r"git\+https://github\.com/[^/]+/llama-stack\.git@v?([0-9]+\.[0-9]+\.[0-9]+(?:rc[0-9]+)?(?:\+rhai[0-9]+)?)"
        git_match = re.search(git_pattern, content)

        if git_match:
            return git_match.group(1)

        print("Error: Could not find llama-stack version in Containerfile")
        exit(1)

    except Exception as e:
        print(f"Error reading Containerfile: {e}")
        exit(1)


def load_external_providers_info():
    """Load build.yaml and extract external provider information."""
    build_yaml_path = REPO_ROOT / "distribution" / "build.yaml"

    if not build_yaml_path.exists():
        print(f"Error: {build_yaml_path} not found")
        exit(1)

    try:
        with open(build_yaml_path, "r") as file:
            build_yaml_data = yaml.safe_load(file)

        # Extract providers section from distribution_spec
        distribution_spec = build_yaml_data.get("distribution_spec", {})
        providers = distribution_spec.get("providers", {})

        # Create a mapping of provider_type to external info
        external_info = {}

        for _, provider_list in providers.items():
            if isinstance(provider_list, list):
                for provider in provider_list:
                    if isinstance(provider, dict) and "provider_type" in provider:
                        provider_type = provider["provider_type"]
                        module_field = provider.get("module", "")

                        if module_field:
                            # Extract version from module field (format: package_name==version)
                            if "==" in module_field:
                                # Handle cases like package[extra]==version
                                version_part = module_field.split("==")[-1]
                                external_info[provider_type] = (
                                    f"Yes (version {version_part})"
                                )
                            else:
                                external_info[provider_type] = "Yes"

        return external_info

    except Exception as e:
        print(f"Error: Error reading build.yaml: {e}")
        exit(1)


def gen_distro_table(providers_data):
    # Start with table header
    table_lines = [
        "| API | Provider | External? | Enabled by default? | How to enable |",
        "|-----|----------|-----------|---------------------|---------------|",
    ]

    # Load external provider information from build.yaml
    external_providers = load_external_providers_info()

    # Create a list to collect all API-Provider pairs for sorting
    api_provider_pairs = []

    # Iterate through each API type and its providers
    for api_name, provider_list in providers_data.items():
        if isinstance(provider_list, list):
            for provider in provider_list:
                if isinstance(provider, dict) and "provider_type" in provider:
                    provider_type = provider["provider_type"]
                    provider_id = provider.get("provider_id", "")

                    # Check if provider_id contains the conditional syntax ${<something>:+<something>}
                    # This regex matches the pattern ${...} containing :+
                    conditional_match = re.search(
                        r"\$\{([^}]*:\+[^}]*)\}", str(provider_id)
                    )

                    if conditional_match:
                        enabled_by_default = "❌"
                        # Extract the environment variable name (part before :+)
                        env_var = conditional_match.group(1).split(":+")[0]
                        # Remove "env." prefix if present
                        if env_var.startswith("env."):
                            env_var = env_var[4:]
                        how_to_enable = f"Set the `{env_var}` environment variable"
                    else:
                        enabled_by_default = "✅"
                        how_to_enable = "N/A"

                    # Determine external status using build.yaml data
                    external_status = external_providers.get(provider_type, "No")

                    api_provider_pairs.append(
                        (
                            api_name,
                            provider_type,
                            external_status,
                            enabled_by_default,
                            how_to_enable,
                        )
                    )

    # Sort first by API name, then by provider type
    api_provider_pairs.sort(key=lambda x: (x[0], x[1]))

    # Add sorted pairs to table
    for (
        api_name,
        provider_type,
        external_status,
        enabled_by_default,
        how_to_enable,
    ) in api_provider_pairs:
        table_lines.append(
            f"| {api_name} | {provider_type} | {external_status} | {enabled_by_default} | {how_to_enable} |"
        )

    return "\n".join(table_lines)


def gen_distro_docs():
    # define distro run.yaml and README.md paths
    run_yaml_path = REPO_ROOT / "distribution" / "run.yaml"
    readme_path = REPO_ROOT / "distribution" / "README.md"

    # check if run.yaml exists
    if not run_yaml_path.exists():
        print(f"Error: {run_yaml_path} not found")
        return 1

    # extract Llama Stack version from Containerfile
    version = extract_llama_stack_version()

    # header section
    header = f"""<!-- This file is automatically generated by scripts/gen_distro_doc.py - do not update manually -->

# Open Data Hub Llama Stack Distribution Image

This image contains the official Open Data Hub Llama Stack distribution, with all the packages and configuration needed to run a Llama Stack server in a containerized environment.

The image is currently shipping with the Open Data Hub version of Llama Stack version [{version}](https://github.com/opendatahub-io/llama-stack/releases/tag/v{version})

You can see an overview of the APIs and Providers the image ships with in the table below.

"""

    try:
        # Load the run.yaml data
        with open(run_yaml_path, "r") as file:
            run_yaml_data = yaml.safe_load(file)

        # Extract providers section
        providers = run_yaml_data.get("providers", {})

        if not providers:
            print("Error: No providers found in run.yaml")
            return 1

        # Generate the Markdown table
        table_content = gen_distro_table(providers)

        # Write to README.md
        with open(readme_path, "w") as readme_file:
            readme_file.write(header + table_content + "\n")

        print(f"Successfully generated {readme_path}")
        print(
            "Ensure you have checked-in any changes to the README to git, or the pre-commit check using this script will fail"
        )
        return 0

    except Exception as e:
        print(f"Error: {e}")
        return 1


if __name__ == "__main__":
    exit(gen_distro_docs())
