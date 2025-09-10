#!/bin/bash

# UC AI Package Utilities
# Common functions for package detection, ordering, and processing
# Used by all installation script generators
# Compatible with bash 3.2+ (macOS default)

# ===================================================
# Package Configuration - Configure all packages here
# ===================================================

# API packages (in dependency order)
declare -a API_PACKAGES=(
    "uc_ai_tools_api"
    "uc_ai_message_api"
    "uc_ai_structured_output"
)

# Provider packages (alphabetical order)
declare -a PROVIDER_PACKAGES=(
    "uc_ai_anthropic"
    "uc_ai_google"
    "uc_ai_oci"
    "uc_ai_ollama"
    "uc_ai_openai"
)

# ===================================================
# Utility Functions
# ===================================================

# Function to get the source directory relative to script location
get_src_dir() {
    local script_dir="$1"
    echo "$(dirname "$script_dir")/src"
}

# Function to check if src directory exists
validate_src_dir() {
    local src_dir="$1"
    
    if [ ! -d "$src_dir" ]; then
        echo "Error: src directory not found at $src_dir"
        return 1
    fi
    return 0
}

# Function to get package description by filename (bash 3.2 compatible)
get_package_description() {
    local filename="$1"
    local package_name
    
    # Remove .pks or .pkb extension
    package_name=$(basename "$filename" .pks)
    package_name=$(basename "$package_name" .pkb)
    
    # Return description based on package name
    case "$package_name" in
        "uc_ai_tools_api")
            echo "Tools API Package"
            ;;
        "uc_ai_message_api")
            echo "Message API Package"
            ;;
        "uc_ai_structured_output")
            echo "Structured Output Package"
            ;;
        "uc_ai_anthropic")
            echo "Anthropic AI Provider Package"
            ;;
        "uc_ai_google")
            echo "Google Gemini AI Provider Package"
            ;;
        "uc_ai_oci")
            echo "OCI AI Provider Package"
            ;;
        "uc_ai_ollama")
            echo "Ollama AI Provider Package"
            ;;
        "uc_ai_openai")
            echo "OpenAI Provider Package"
            ;;
        "uc_ai")
            echo "Core UC AI Package"
            ;;
        *)
            echo "$package_name Package"
            ;;
    esac
}

# Function to get all package specifications in installation order
# Returns: space-separated list of .pks files in dependency order
get_package_specs_ordered() {
    local src_dir="$1"
    local specs=()
    
    # 1. Core types package first (uc_ai.pks contains the main types)
    if [ -f "$src_dir/packages/uc_ai.pks" ]; then
        specs+=("$src_dir/packages/uc_ai.pks")
    fi
    
    # 2. API packages (in dependency order)
    for api_pkg in "${API_PACKAGES[@]}"; do
        if [ -f "$src_dir/packages/${api_pkg}.pks" ]; then
            specs+=("$src_dir/packages/${api_pkg}.pks")
        fi
    done
    
    # 3. Provider packages (alphabetical order)
    for provider_pkg in "${PROVIDER_PACKAGES[@]}"; do
        if [ -f "$src_dir/packages/${provider_pkg}.pks" ]; then
            specs+=("$src_dir/packages/${provider_pkg}.pks")
        fi
    done
    
    printf '%s\n' "${specs[@]}"
}

# Function to get all package bodies in installation order
# Returns: space-separated list of .pkb files in dependency order
get_package_bodies_ordered() {
    local src_dir="$1"
    local bodies=()
    
    # 1. API packages first (in dependency order)
    for api_pkg in "${API_PACKAGES[@]}"; do
        if [ -f "$src_dir/packages/${api_pkg}.pkb" ]; then
            bodies+=("$src_dir/packages/${api_pkg}.pkb")
        fi
    done
    
    # 2. Provider packages (alphabetical order)
    for provider_pkg in "${PROVIDER_PACKAGES[@]}"; do
        if [ -f "$src_dir/packages/${provider_pkg}.pkb" ]; then
            bodies+=("$src_dir/packages/${provider_pkg}.pkb")
        fi
    done
    
    # 3. Core package body last (depends on others)
    if [ -f "$src_dir/packages/uc_ai.pkb" ]; then
        bodies+=("$src_dir/packages/uc_ai.pkb")
    fi
    
    printf '%s\n' "${bodies[@]}"
}

# Function to check if a package is an API package
is_api_package() {
    local filename="$1"
    local package_name
    
    package_name=$(basename "$filename" .pks)
    package_name=$(basename "$package_name" .pkb)
    
    for api_pkg in "${API_PACKAGES[@]}"; do
        if [[ "$package_name" == "$api_pkg" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if a package is a provider package
is_provider_package() {
    local filename="$1"
    local package_name
    
    package_name=$(basename "$filename" .pks)
    package_name=$(basename "$package_name" .pkb)
    
    for provider_pkg in "${PROVIDER_PACKAGES[@]}"; do
        if [[ "$package_name" == "$provider_pkg" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if a package is the core package
is_core_package() {
    local filename="$1"
    local package_name
    
    package_name=$(basename "$filename" .pks)
    package_name=$(basename "$package_name" .pkb)
    
    [[ "$package_name" == "uc_ai" ]]
}

# Function to get package type (core, api, provider)
get_package_type() {
    local filename="$1"
    
    if is_core_package "$filename"; then
        echo "core"
    elif is_api_package "$filename"; then
        echo "api"
    elif is_provider_package "$filename"; then
        echo "provider"
    else
        echo "unknown"
    fi
}

# Function to list installed packages for reporting
list_installed_packages() {
    local src_dir="$1"
    local show_descriptions="${2:-false}"
    
    echo "Package specifications:"
    while IFS= read -r spec_file; do
        local filename=$(basename "$spec_file")
        if [[ "$show_descriptions" == "true" ]]; then
            local desc=$(get_package_description "$filename")
            echo "  ✓ src/packages/$filename ($desc)"
        else
            echo "  ✓ src/packages/$filename"
        fi
    done < <(get_package_specs_ordered "$src_dir")
    
    echo "Package bodies:"
    while IFS= read -r body_file; do
        local filename=$(basename "$body_file")
        if [[ "$show_descriptions" == "true" ]]; then
            local desc=$(get_package_description "$filename")
            echo "  ✓ src/packages/$filename ($desc)"
        else
            echo "  ✓ src/packages/$filename"
        fi
    done < <(get_package_bodies_ordered "$src_dir")
}

# Function to get all packages by type
get_packages_by_type() {
    local src_dir="$1"
    local package_type="$2"  # core, api, provider
    local extension="$3"     # pks or pkb
    local packages=()
    
    case "$package_type" in
        "core")
            if [ -f "$src_dir/packages/uc_ai.$extension" ]; then
                packages+=("$src_dir/packages/uc_ai.$extension")
            fi
            ;;
        "api")
            for api_pkg in "${API_PACKAGES[@]}"; do
                if [ -f "$src_dir/packages/${api_pkg}.$extension" ]; then
                    packages+=("$src_dir/packages/${api_pkg}.$extension")
                fi
            done
            ;;
        "provider")
            for provider_pkg in "${PROVIDER_PACKAGES[@]}"; do
                if [ -f "$src_dir/packages/${provider_pkg}.$extension" ]; then
                    packages+=("$src_dir/packages/${provider_pkg}.$extension")
                fi
            done
            ;;
    esac
    
    printf '%s\n' "${packages[@]}"
}

# Function to validate package configuration
validate_package_config() {
    local src_dir="$1"
    local errors=0
    
    echo "Validating package configuration..."
    
    # Check core package
    if [ ! -f "$src_dir/packages/uc_ai.pks" ]; then
        echo "ERROR: Core package specification uc_ai.pks not found"
        ((errors++))
    fi
    if [ ! -f "$src_dir/packages/uc_ai.pkb" ]; then
        echo "ERROR: Core package body uc_ai.pkb not found"
        ((errors++))
    fi
    
    # Check API packages
    for api_pkg in "${API_PACKAGES[@]}"; do
        if [ ! -f "$src_dir/packages/${api_pkg}.pks" ]; then
            echo "WARNING: API package specification ${api_pkg}.pks not found"
        fi
        if [ ! -f "$src_dir/packages/${api_pkg}.pkb" ]; then
            echo "WARNING: API package body ${api_pkg}.pkb not found"
        fi
    done
    
    # Check provider packages
    for provider_pkg in "${PROVIDER_PACKAGES[@]}"; do
        if [ ! -f "$src_dir/packages/${provider_pkg}.pks" ]; then
            echo "WARNING: Provider package specification ${provider_pkg}.pks not found"
        fi
        if [ ! -f "$src_dir/packages/${provider_pkg}.pkb" ]; then
            echo "WARNING: Provider package body ${provider_pkg}.pkb not found"
        fi
    done
    
    # Check for unknown packages
    for pks_file in "$src_dir/packages/"*.pks; do
        if [ -f "$pks_file" ]; then
            local filename=$(basename "$pks_file")
            local package_name=$(basename "$filename" .pks)
            local type=$(get_package_type "$filename")
            if [[ "$type" == "unknown" ]]; then
                echo "WARNING: Unknown package found: $filename (not in configuration)"
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        echo "Package configuration validation complete - no errors"
    else
        echo "Package configuration validation failed with $errors errors"
        return 1
    fi
    
    return 0
}

# Export arrays for use in other scripts
export API_PACKAGES
export PROVIDER_PACKAGES
