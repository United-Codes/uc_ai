#!/bin/bash

# Script to generate install_uc_ai.sql by scanning the src directory structure
# This ensures all files are included in the correct installation order

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/install_uc_ai.sql"
SRC_DIR="${SCRIPT_DIR}/src"

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
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    if [ -f "$SRC_DIR/packages/${api_pkg}.pks" ]; then
        echo "@@src/packages/${api_pkg}.pks" >> "$OUTPUT_FILE"
    fi
done
echo "" >> "$OUTPUT_FILE"

# 4. Provider packages (alphabetical order)
echo "PROMPT - Installing AI provider package specifications..." >> "$OUTPUT_FILE"
for provider_pks in "$SRC_DIR/packages/"*anthropic*.pks "$SRC_DIR/packages/"*google*.pks "$SRC_DIR/packages/"*openai*.pks; do
    if [ -f "$provider_pks" ]; then
        provider_file=$(basename "$provider_pks")
        echo "@@src/packages/${provider_file}" >> "$OUTPUT_FILE"
    fi
done
echo "" >> "$OUTPUT_FILE"

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE"

# API packages first
echo "PROMPT - Installing API package bodies..." >> "$OUTPUT_FILE"
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    if [ -f "$SRC_DIR/packages/${api_pkg}.pkb" ]; then
        echo "@@src/packages/${api_pkg}.pkb" >> "$OUTPUT_FILE"
    fi
done

# Provider packages
echo "PROMPT - Installing AI provider package bodies..." >> "$OUTPUT_FILE"
for provider_pkb in "$SRC_DIR/packages/"*anthropic*.pkb "$SRC_DIR/packages/"*google*.pkb "$SRC_DIR/packages/"*openai*.pkb; do
    if [ -f "$provider_pkb" ]; then
        provider_file=$(basename "$provider_pkb")
        echo "@@src/packages/${provider_file}" >> "$OUTPUT_FILE"
    fi
done

# Core package body last (depends on others)
if [ -f "$SRC_DIR/packages/uc_ai.pkb" ]; then
    echo "PROMPT - Installing core UC AI package body..." >> "$OUTPUT_FILE"
    echo "@@src/packages/uc_ai.pkb" >> "$OUTPUT_FILE"
fi

echo "" >> "$OUTPUT_FILE"
echo "PROMPT ===================================================" >> "$OUTPUT_FILE"
echo "PROMPT UC AI Framework installation complete!" >> "$OUTPUT_FILE"
echo "PROMPT" >> "$OUTPUT_FILE"
echo "PROMPT Available AI providers:" >> "$OUTPUT_FILE"
echo "PROMPT - OpenAI GPT models" >> "$OUTPUT_FILE"
echo "PROMPT - Anthropic Claude models" >> "$OUTPUT_FILE"
echo "PROMPT - Google Gemini models" >> "$OUTPUT_FILE"
echo "PROMPT" >> "$OUTPUT_FILE"
echo "PROMPT Use uc_ai.generate_text() to start generating AI responses" >> "$OUTPUT_FILE"
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
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    [ -f "$SRC_DIR/packages/${api_pkg}.pks" ] && echo "  - src/packages/${api_pkg}.pks"
done
for provider_pks in "$SRC_DIR/packages/"*anthropic*.pks "$SRC_DIR/packages/"*google*.pks "$SRC_DIR/packages/"*openai*.pks; do
    if [ -f "$provider_pks" ]; then
        echo "  - src/packages/$(basename "$provider_pks")"
    fi
done

echo "Package bodies:"
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    [ -f "$SRC_DIR/packages/${api_pkg}.pkb" ] && echo "  - src/packages/${api_pkg}.pkb"
done
for provider_pkb in "$SRC_DIR/packages/"*anthropic*.pkb "$SRC_DIR/packages/"*google*.pkb "$SRC_DIR/packages/"*openai*.pkb; do
    if [ -f "$provider_pkb" ]; then
        echo "  - src/packages/$(basename "$provider_pkb")"
    fi
done
[ -f "$SRC_DIR/packages/uc_ai.pkb" ] && echo "  - src/packages/uc_ai.pkb"

echo ""
echo "Installation order ensures proper dependency resolution."
