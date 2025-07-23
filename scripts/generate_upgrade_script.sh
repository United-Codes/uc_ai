#!/bin/bash

# Script to generate upgrade_packages.sql containing only package files
# This is useful for upgrading existing installations without recreating tables/triggers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="${ROOT_DIR}/upgrade_packages.sql"
SRC_DIR="${ROOT_DIR}/src"

# Check if src directory exists
if [ ! -d "$SRC_DIR" ]; then
    echo "Error: src directory not found at $SRC_DIR"
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
add_file_content "$SRC_DIR/packages/uc_ai.pks" "Core UC AI Package Specification - Types and Constants"

# 2. Dependencies (utility functions)
echo "PROMPT - Upgrading utility functions..." >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/dependencies/key_function.sql" "Utility Functions"

# 3. API packages (tools and message APIs)
echo "PROMPT - Upgrading API package specifications..." >> "$OUTPUT_FILE"
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    if [ -f "$SRC_DIR/packages/${api_pkg}.pks" ]; then
        case "$api_pkg" in
            "uc_ai_tools_api")
                add_file_content "$SRC_DIR/packages/${api_pkg}.pks" "Tools API Package Specification"
                ;;
            "uc_ai_message_api")
                add_file_content "$SRC_DIR/packages/${api_pkg}.pks" "Message API Package Specification"
                ;;
        esac
    fi
done

# 4. Provider packages (alphabetical order)
echo "PROMPT - Upgrading AI provider package specifications..." >> "$OUTPUT_FILE"
for provider_pks in "$SRC_DIR/packages/"*anthropic*.pks "$SRC_DIR/packages/"*google*.pks "$SRC_DIR/packages/"*openai*.pks; do
    if [ -f "$provider_pks" ]; then
        provider_file=$(basename "$provider_pks")
        case "$provider_file" in
            *anthropic*)
                add_file_content "$provider_pks" "Anthropic AI Provider Package Specification"
                ;;
            *google*)
                add_file_content "$provider_pks" "Google Gemini AI Provider Package Specification"
                ;;
            *openai*)
                add_file_content "$provider_pks" "OpenAI Provider Package Specification"
                ;;
        esac
    fi
done

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# API packages first
echo "PROMPT - Upgrading API package bodies..." >> "$OUTPUT_FILE"
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    if [ -f "$SRC_DIR/packages/${api_pkg}.pkb" ]; then
        case "$api_pkg" in
            "uc_ai_tools_api")
                add_file_content "$SRC_DIR/packages/${api_pkg}.pkb" "Tools API Package Body - Implementation"
                ;;
            "uc_ai_message_api")
                add_file_content "$SRC_DIR/packages/${api_pkg}.pkb" "Message API Package Body - Implementation"
                ;;
        esac
    fi
done

# Provider packages
echo "PROMPT - Upgrading AI provider package bodies..." >> "$OUTPUT_FILE"
for provider_pkb in "$SRC_DIR/packages/"*anthropic*.pkb "$SRC_DIR/packages/"*google*.pkb "$SRC_DIR/packages/"*openai*.pkb; do
    if [ -f "$provider_pkb" ]; then
        provider_file=$(basename "$provider_pkb")
        case "$provider_file" in
            *anthropic*)
                add_file_content "$provider_pkb" "Anthropic AI Provider Package Body - Implementation"
                ;;
            *google*)
                add_file_content "$provider_pkb" "Google Gemini AI Provider Package Body - Implementation"
                ;;
            *openai*)
                add_file_content "$provider_pkb" "OpenAI Provider Package Body - Implementation"
                ;;
        esac
    fi
done

# Core package body last (depends on others)
echo "PROMPT - Upgrading core UC AI package body..." >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/packages/uc_ai.pkb" "Core UC AI Package Body - Main Implementation"

# Final completion message
cat >> "$OUTPUT_FILE" << 'EOF'

PROMPT ===================================================
PROMPT UC AI Framework package upgrade complete!
PROMPT
PROMPT Upgraded components:
PROMPT - All AI provider packages (OpenAI, Anthropic, Google)
PROMPT - API packages (tools and message APIs)
PROMPT - Core UC AI package
PROMPT - Utility functions
PROMPT
PROMPT Your existing data and configuration remain unchanged.
PROMPT ===================================================
EOF

echo "Generated upgrade_packages.sql successfully!"
echo ""
echo "Package upgrade script created with the following components:"

# Show what was included
echo "Dependencies:"
[ -f "$SRC_DIR/dependencies/key_function.sql" ] && echo "  ✓ src/dependencies/key_function.sql"

echo "Package specifications:"
[ -f "$SRC_DIR/packages/uc_ai.pks" ] && echo "  ✓ src/packages/uc_ai.pks"
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    [ -f "$SRC_DIR/packages/${api_pkg}.pks" ] && echo "  ✓ src/packages/${api_pkg}.pks"
done
for provider_pks in "$SRC_DIR/packages/"*anthropic*.pks "$SRC_DIR/packages/"*google*.pks "$SRC_DIR/packages/"*openai*.pks; do
    if [ -f "$provider_pks" ]; then
        echo "  ✓ src/packages/$(basename "$provider_pks")"
    fi
done

echo "Package bodies:"
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    [ -f "$SRC_DIR/packages/${api_pkg}.pkb" ] && echo "  ✓ src/packages/${api_pkg}.pkb"
done
for provider_pkb in "$SRC_DIR/packages/"*anthropic*.pkb "$SRC_DIR/packages/"*google*.pkb "$SRC_DIR/packages/"*openai*.pkb; do
    if [ -f "$provider_pkb" ]; then
        echo "  ✓ src/packages/$(basename "$provider_pkb")"
    fi
done
[ -f "$SRC_DIR/packages/uc_ai.pkb" ] && echo "  ✓ src/packages/uc_ai.pkb"

echo ""
echo "This script is ideal for:"
echo "- Upgrading existing UC AI installations"
echo "- Applying package fixes without touching data"
echo "- Development and testing environments"
echo ""
echo "Output file: $OUTPUT_FILE"
