#!/bin/bash

# Script to generate install_uc_ai.sql by scanning the src directory structure
# This ensures all files are included in the correct installation order

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/../install_uc_ai.sql"
SRC_DIR="${SCRIPT_DIR}/../src"

# Check if src directory exists
if [ ! -d "$SRC_DIR" ]; then
    echo "Error: src directory not found at $SRC_DIR"
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
if [ -f "$SRC_DIR/packages/uc_ai.pks" ]; then
    echo "PROMPT - Installing core types and constants..." >> "$OUTPUT_FILE"
    echo "@@src/packages/uc_ai.pks" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# 2. Dependencies
if [ -f "$SRC_DIR/dependencies/key_function.sql" ]; then
    echo "PROMPT - Installing utility functions..." >> "$OUTPUT_FILE"
    echo "@@src/dependencies/key_function.sql" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# 3. API packages (tools and message APIs)
echo "PROMPT - Installing API package specifications..." >> "$OUTPUT_FILE"
for pks_file in "$SRC_DIR/packages/"*_api.pks; do
    if [ -f "$pks_file" ]; then
        pks_filename=$(basename "$pks_file")
        echo "@@src/packages/${pks_filename}" >> "$OUTPUT_FILE"
    fi
done
echo "" >> "$OUTPUT_FILE"

# 4. Provider packages (all other .pks files except uc_ai.pks and API packages)
echo "PROMPT - Installing AI provider package specifications..." >> "$OUTPUT_FILE"
for pks_file in "$SRC_DIR/packages/"*.pks; do
    pks_filename=$(basename "$pks_file")
    # Skip uc_ai.pks (already installed) and API packages (already installed)
    if [[ "$pks_filename" != "uc_ai.pks" && "$pks_filename" != *"_api.pks" ]]; then
        echo "@@src/packages/${pks_filename}" >> "$OUTPUT_FILE"
    fi
done
echo "" >> "$OUTPUT_FILE"

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE"

# API packages first
echo "PROMPT - Installing API package bodies..." >> "$OUTPUT_FILE"
for pkb_file in "$SRC_DIR/packages/"*_api.pkb; do
    if [ -f "$pkb_file" ]; then
        pkb_filename=$(basename "$pkb_file")
        echo "@@src/packages/${pkb_filename}" >> "$OUTPUT_FILE"
    fi
done

# Provider packages
echo "PROMPT - Installing AI provider package bodies..." >> "$OUTPUT_FILE"
for pkb_file in "$SRC_DIR/packages/"*.pkb; do
    pkb_filename=$(basename "$pkb_file")
    # Skip uc_ai.pkb (installed last) and API packages (already installed)
    if [[ "$pkb_filename" != "uc_ai.pkb" && "$pkb_filename" != *"_api.pkb" ]]; then
        echo "@@src/packages/${pkb_filename}" >> "$OUTPUT_FILE"
    fi
done

# Core package body last (depends on others)
if [ -f "$SRC_DIR/packages/uc_ai.pkb" ]; then
    echo "PROMPT - Installing core UC AI package body..." >> "$OUTPUT_FILE"
    echo "@@src/packages/uc_ai.pkb" >> "$OUTPUT_FILE"
fi

echo "" >> "$OUTPUT_FILE"
echo "PROMPT ===================================================" >> "$OUTPUT_FILE"
echo "PROMPT UC AI installation complete!" >> "$OUTPUT_FILE"
echo "PROMPT Refer to the documentation for usage instructions: https://www.united-codes.com/products/uc-ai/docs/" >> "$OUTPUT_FILE"
echo "PROMPT ===================================================" >> "$OUTPUT_FILE"

echo "Generated install_uc_ai.sql successfully!"
echo ""
echo "Files included:"

# Show what was included
echo "Tables:"
[ -f "$SRC_DIR/tables/install.sql" ] && echo "  - src/tables/install.sql"

echo "Triggers:"
[ -f "$SRC_DIR/triggers/triggers.sql" ] && echo "  - src/triggers/triggers.sql"

echo "Dependencies:"
[ -f "$SRC_DIR/dependencies/key_function.sql" ] && echo "  - src/dependencies/key_function.sql"

echo "Package specifications:"
[ -f "$SRC_DIR/packages/uc_ai.pks" ] && echo "  - src/packages/uc_ai.pks"
for pks_file in "$SRC_DIR/packages/"*_api.pks; do
    if [ -f "$pks_file" ]; then
        echo "  - src/packages/$(basename "$pks_file")"
    fi
done
for pks_file in "$SRC_DIR/packages/"*.pks; do
    pks_filename=$(basename "$pks_file")
    if [[ "$pks_filename" != "uc_ai.pks" && "$pks_filename" != *"_api.pks" ]]; then
        echo "  - src/packages/$pks_filename"
    fi
done

echo "Package bodies:"
for pkb_file in "$SRC_DIR/packages/"*_api.pkb; do
    if [ -f "$pkb_file" ]; then
        echo "  - src/packages/$(basename "$pkb_file")"
    fi
done
for pkb_file in "$SRC_DIR/packages/"*.pkb; do
    pkb_filename=$(basename "$pkb_file")
    if [[ "$pkb_filename" != "uc_ai.pkb" && "$pkb_filename" != *"_api.pkb" ]]; then
        echo "  - src/packages/$pkb_filename"
    fi
done
[ -f "$SRC_DIR/packages/uc_ai.pkb" ] && echo "  - src/packages/uc_ai.pkb"

echo ""
echo "Installation order ensures proper dependency resolution."
