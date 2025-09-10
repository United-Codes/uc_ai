#!/bin/bash

# Script to generate install_uc_ai.sql by scanning the src directory structure
# This ensures all files are included in the correct installation order

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared package utilities
source "$SCRIPT_DIR/package_utils.sh"

OUTPUT_FILE="${SCRIPT_DIR}/../install_uc_ai.sql"
SRC_DIR=$(get_src_dir "$SCRIPT_DIR")

# Validate src directory exists
if ! validate_src_dir "$SRC_DIR"; then
    exit 1
fi

echo "Generating install_uc_ai.sql..."

# Start writing the install script
cat > "$OUTPUT_FILE" << 'EOF'
-- UC AI Framework Installation Script
-- Run this script to install the complete framework with OpenAI and Anthropic support

PROMPT ===================================================
PROMPT UC AI Framework Installation Starting...
PROMPT ===================================================

EOF

# Install tables first
if [ -f "$SRC_DIR/tables/install.sql" ]; then
    echo "PROMPT Installing UC AI Framework Tables..." >> "$OUTPUT_FILE"
    echo "PROMPT This creates the core database tables for message storage and configuration" >> "$OUTPUT_FILE"
    echo "@@src/tables/install.sql" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# Install triggers if they exist
if [ -f "$SRC_DIR/triggers/triggers.sql" ]; then
    echo "PROMPT Installing database triggers..." >> "$OUTPUT_FILE"
    echo "PROMPT This sets up automatic data validation and logging triggers" >> "$OUTPUT_FILE"
    echo "@@src/triggers/triggers.sql" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

echo "PROMPT Installing PL/SQL packages..." >> "$OUTPUT_FILE"
echo "PROMPT This includes all AI provider packages and utility functions" >> "$OUTPUT_FILE"

# Install package specifications first (in dependency order)
echo "" >> "$OUTPUT_FILE"
echo "PROMPT Installing package specifications (headers)..." >> "$OUTPUT_FILE"

# 1. Core types package first (uc_ai.pks contains the main types)
echo "PROMPT - Installing core types and constants..." >> "$OUTPUT_FILE"
while IFS= read -r spec_file; do
    if is_core_package "$(basename "$spec_file")"; then
        echo "@@src/packages/$(basename "$spec_file")" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        break
    fi
done < <(get_package_specs_ordered "$SRC_DIR")

# 2. Dependencies
if [ -f "$SRC_DIR/dependencies/key_function.sql" ]; then
    echo "PROMPT - Installing utility functions..." >> "$OUTPUT_FILE"
    echo "@@src/dependencies/key_function.sql" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# 3. API packages (tools and message APIs)
echo "PROMPT - Installing API package specifications..." >> "$OUTPUT_FILE"
while IFS= read -r spec_file; do
    if is_api_package "$(basename "$spec_file")"; then
        echo "@@src/packages/$(basename "$spec_file")" >> "$OUTPUT_FILE"
    fi
done < <(get_package_specs_ordered "$SRC_DIR")
echo "" >> "$OUTPUT_FILE"

# 4. Provider packages (all other .pks files except uc_ai.pks and API packages)
echo "PROMPT - Installing AI provider package specifications..." >> "$OUTPUT_FILE"
while IFS= read -r spec_file; do
    if is_provider_package "$(basename "$spec_file")"; then
        echo "@@src/packages/$(basename "$spec_file")" >> "$OUTPUT_FILE"
    fi
done < <(get_package_specs_ordered "$SRC_DIR")
echo "" >> "$OUTPUT_FILE"

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE"

# API packages first
echo "PROMPT - Installing API package bodies..." >> "$OUTPUT_FILE"
while IFS= read -r body_file; do
    if is_api_package "$(basename "$body_file")"; then
        echo "@@src/packages/$(basename "$body_file")" >> "$OUTPUT_FILE"
    fi
done < <(get_package_bodies_ordered "$SRC_DIR")

# Provider packages
echo "PROMPT - Installing AI provider package bodies..." >> "$OUTPUT_FILE"
while IFS= read -r body_file; do
    if is_provider_package "$(basename "$body_file")"; then
        echo "@@src/packages/$(basename "$body_file")" >> "$OUTPUT_FILE"
    fi
done < <(get_package_bodies_ordered "$SRC_DIR")

# Core package body last (depends on others)
echo "PROMPT - Installing core UC AI package body..." >> "$OUTPUT_FILE"
while IFS= read -r body_file; do
    if is_core_package "$(basename "$body_file")"; then
        echo "@@src/packages/$(basename "$body_file")" >> "$OUTPUT_FILE"
        break
    fi
done < <(get_package_bodies_ordered "$SRC_DIR")

echo "" >> "$OUTPUT_FILE"
echo "PROMPT ===================================================" >> "$OUTPUT_FILE"
echo "PROMPT UC AI installation complete!" >> "$OUTPUT_FILE"
echo "PROMPT Refer to the documentation for usage instructions: https://www.united-codes.com/products/uc-ai/docs/" >> "$OUTPUT_FILE"
echo "PROMPT ===================================================" >> "$OUTPUT_FILE"

echo "Generated install_uc_ai.sql successfully!"
echo ""
echo "Files included:"

# Show what was included using the shared utility
echo "Tables:"
[ -f "$SRC_DIR/tables/install.sql" ] && echo "  - src/tables/install.sql"

echo "Triggers:"
[ -f "$SRC_DIR/triggers/triggers.sql" ] && echo "  - src/triggers/triggers.sql"

echo "Dependencies:"
[ -f "$SRC_DIR/dependencies/key_function.sql" ] && echo "  - src/dependencies/key_function.sql"

list_installed_packages "$SRC_DIR" false

echo ""
echo "Installation order ensures proper dependency resolution."
