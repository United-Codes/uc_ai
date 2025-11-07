#!/bin/bash

# Script to generate upgrade_packages.sql containing only package files
# This is useful for upgrading existing installations without recreating tables/triggers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared package utilities
source "$SCRIPT_DIR/package_utils.sh"

ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="${ROOT_DIR}/upgrade_packages.sql"
SRC_DIR=$(get_src_dir "$SCRIPT_DIR")

# Validate src directory exists
if ! validate_src_dir "$SRC_DIR"; then
    exit 1
fi

echo "Generating upgrade_packages.sql with inlined package content..."

# Function to add file content with header
add_file_content() {
    local file_path="$1"
    local description="$2"
    
    if [ -f "$file_path" ]; then
        echo "" >> "$OUTPUT_FILE"
        echo "-- ====================================================" >> "$OUTPUT_FILE"
        echo "-- $description" >> "$OUTPUT_FILE"
        echo "-- File: $(basename "$file_path")" >> "$OUTPUT_FILE"
        echo "-- ====================================================" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        cat "$file_path" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        return 0
    else
        echo "Warning: File not found: $file_path"
        return 1
    fi
}

# Start writing the upgrade script with inlined content
cat > "$OUTPUT_FILE" << 'EOF'
-- UC AI Framework Complete Package Upgrade Script
-- This is a self-contained script with all package contents inlined
-- Run this script to upgrade package specifications and bodies only
-- This assumes tables and triggers are already installed

PROMPT ===================================================
PROMPT UC AI Framework Package Upgrade Starting...
PROMPT ===================================================

PROMPT This script will upgrade the following components:
PROMPT - Core UC AI package and all provider packages
PROMPT - API packages (tools and message APIs)
PROMPT - Utility functions
PROMPT
PROMPT Tables and triggers will NOT be modified.
PROMPT ===================================================

EOF

# Install package specifications first (in dependency order)
echo "PROMPT Installing package specifications (headers)..." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# 1. Core types package first (uc_ai.pks contains the main types)
echo "PROMPT - Upgrading core types and constants..." >> "$OUTPUT_FILE"
while IFS= read -r spec_file; do
    if is_core_package "$(basename "$spec_file")"; then
        add_file_content "$spec_file" "Core UC AI Package Specification - Types and Constants"
        break
    fi
done < <(get_package_specs_ordered "$SRC_DIR")

# 2. API packages (tools and message APIs)
echo "PROMPT - Upgrading API package specifications..." >> "$OUTPUT_FILE"
while IFS= read -r spec_file; do
    if is_api_package "$(basename "$spec_file")"; then
        desc=$(get_package_description "$(basename "$spec_file")")
        add_file_content "$spec_file" "$desc Specification"
    fi
done < <(get_package_specs_ordered "$SRC_DIR")

# 3. Provider packages (alphabetical order)
echo "PROMPT - Upgrading AI provider package specifications..." >> "$OUTPUT_FILE"
while IFS= read -r spec_file; do
    if is_provider_package "$(basename "$spec_file")"; then
        desc=$(get_package_description "$(basename "$spec_file")")
        add_file_content "$spec_file" "$desc Specification"
    fi
done < <(get_package_specs_ordered "$SRC_DIR")

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# API packages first
echo "PROMPT - Upgrading API package bodies..." >> "$OUTPUT_FILE"
while IFS= read -r body_file; do
    if is_api_package "$(basename "$body_file")"; then
        desc=$(get_package_description "$(basename "$body_file")")
        add_file_content "$body_file" "$desc Body - Implementation"
    fi
done < <(get_package_bodies_ordered "$SRC_DIR")

# Provider packages
echo "PROMPT - Upgrading AI provider package bodies..." >> "$OUTPUT_FILE"
while IFS= read -r body_file; do
    if is_provider_package "$(basename "$body_file")"; then
        desc=$(get_package_description "$(basename "$body_file")")
        add_file_content "$body_file" "$desc Body - Implementation"
    fi
done < <(get_package_bodies_ordered "$SRC_DIR")

# Core package body last (depends on others)
echo "PROMPT - Upgrading core UC AI package body..." >> "$OUTPUT_FILE"
while IFS= read -r body_file; do
    if is_core_package "$(basename "$body_file")"; then
        add_file_content "$body_file" "Core UC AI Package Body - Main Implementation"
        break
    fi
done < <(get_package_bodies_ordered "$SRC_DIR")

# Run post-installation scripts
if [ -d "$SRC_DIR/post-scripts" ]; then
    echo "PROMPT Running post-installation scripts..." >> "$OUTPUT_FILE"
    for post_script in "$SRC_DIR/post-scripts"/*.sql; do
        if [ -f "$post_script" ]; then
            desc="Post-installation script - $(basename "$post_script")"
            add_file_content "$post_script" "$desc"
        fi
    done
fi

# Final completion message
cat >> "$OUTPUT_FILE" << 'EOF'

PROMPT ===================================================
PROMPT UC AI package upgrade complete!
PROMPT Refer to the documentation for usage instructions: https://www.united-codes.com/products/uc-ai/docs/
PROMPT ===================================================
EOF

echo "Generated upgrade_packages.sql successfully!"
echo ""
echo "Package upgrade script created with the following components:"

# Show what was included using the shared utility
list_installed_packages "$SRC_DIR" true

echo ""
echo "This script is ideal for:"
echo "- Upgrading existing UC AI installations"
echo "- Applying package fixes without touching data"
echo "- Development and testing environments"
echo ""
echo "Output file: $OUTPUT_FILE"
