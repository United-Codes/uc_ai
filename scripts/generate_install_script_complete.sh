#!/bin/bash

# Script to generate install_uc_ai_complete.sql by inlining all source files
# This creates a single self-contained SQL script with all file contents embedded

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="${ROOT_DIR}/install_uc_ai_complete.sql"
SRC_DIR="${ROOT_DIR}/src"

# Check if src directory exists
if [ ! -d "$SRC_DIR" ]; then
    echo "Error: src directory not found at $SRC_DIR"
    exit 1
fi

echo "Generating install_uc_ai_complete.sql with inlined content..."

# Function to add file content with header
add_file_content() {
    local file_path="$1"
    local description="$2"
    local output_file="${3:-$OUTPUT_FILE}"
    
    if [ -f "$file_path" ]; then
        echo "" >> "$output_file"
        echo "-- ====================================================" >> "$output_file"
        echo "-- $description" >> "$output_file"
        echo "-- File: $(basename "$file_path")" >> "$output_file"
        echo "-- ====================================================" >> "$output_file"
        echo "" >> "$output_file"
        cat "$file_path" >> "$output_file"
        echo "" >> "$output_file"
        return 0
    else
        echo "Warning: File not found: $file_path"
        return 1
    fi
}

# Start writing the install script
cat > "$OUTPUT_FILE" << 'EOF'
-- UC AI Framework Complete Installation Script
-- This is a self-contained script with all file contents inlined
-- Run this script to install the complete framework with OpenAI, Anthropic, and Google support

PROMPT ===================================================
PROMPT UC AI Framework Installation Starting...
PROMPT ===================================================

EOF

# Install tables first
echo "PROMPT Installing UC AI Framework Tables..." >> "$OUTPUT_FILE"
echo "PROMPT This creates the core database tables for message storage and configuration" >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/tables/install.sql" "UC AI Framework Tables"

# Install triggers if they exist
if [ -f "$SRC_DIR/triggers/triggers.sql" ]; then
    echo "PROMPT Installing database triggers..." >> "$OUTPUT_FILE"
    echo "PROMPT This sets up automatic data validation and logging triggers" >> "$OUTPUT_FILE"
    add_file_content "$SRC_DIR/triggers/triggers.sql" "Database Triggers"
fi

echo "PROMPT Installing PL/SQL packages..." >> "$OUTPUT_FILE"
echo "PROMPT This includes all AI provider packages and utility functions" >> "$OUTPUT_FILE"

# Install package specifications first (in dependency order)
echo "" >> "$OUTPUT_FILE"
echo "PROMPT Installing package specifications (headers)..." >> "$OUTPUT_FILE"

# 1. Core types package first (uc_ai.pks contains the main types)
echo "PROMPT - Installing core types and constants..." >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/packages/uc_ai.pks" "Core UC AI Package Specification - Types and Constants"

# 2. Dependencies
echo "PROMPT - Installing utility functions..." >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/dependencies/key_function.sql" "Utility Functions"

# 3. API packages (tools and message APIs)
echo "PROMPT - Installing API package specifications..." >> "$OUTPUT_FILE"
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
echo "PROMPT - Installing AI provider package specifications..." >> "$OUTPUT_FILE"
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

# API packages first
echo "PROMPT - Installing API package bodies..." >> "$OUTPUT_FILE"
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
echo "PROMPT - Installing AI provider package bodies..." >> "$OUTPUT_FILE"
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
echo "PROMPT - Installing core UC AI package body..." >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/packages/uc_ai.pkb" "Core UC AI Package Body - Main Implementation"

# Final completion message
cat >> "$OUTPUT_FILE" << 'EOF'

PROMPT ===================================================
PROMPT UC AI Framework installation complete!
PROMPT
PROMPT Available AI providers:
PROMPT - OpenAI GPT models
PROMPT - Anthropic Claude models  
PROMPT - Google Gemini models
PROMPT
PROMPT Use uc_ai.generate_text() to start generating AI responses
PROMPT ===================================================
EOF

echo "Generated install_uc_ai_complete.sql successfully!"
echo ""
echo "Complete installation script created with inlined content from:"

# Show what was included
echo "Tables:"
[ -f "$SRC_DIR/tables/install.sql" ] && echo "  ✓ src/tables/install.sql"

echo "Triggers:"
[ -f "$SRC_DIR/triggers/triggers.sql" ] && echo "  ✓ src/triggers/triggers.sql"

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
echo "The complete script is self-contained and ready to run without external file dependencies."
echo "Output file: $OUTPUT_FILE"

echo ""
echo "Generating install_uc_ai_complete_with_logger.sql with logger included..."

# Generate the complete script with logger
OUTPUT_FILE_WITH_LOGGER="${ROOT_DIR}/install_uc_ai_complete_with_logger.sql"

# Start writing the install script with logger
cat > "$OUTPUT_FILE_WITH_LOGGER" << 'EOF'
-- UC AI Framework Complete Installation Script with Logger
-- This is a self-contained script with all file contents inlined including the logger
-- Run this script to install the complete framework with OpenAI, Anthropic, Google support and Logger

PROMPT ===================================================
PROMPT UC AI Framework with Logger Installation Starting...
PROMPT ===================================================

EOF

# First install the logger
echo "PROMPT Installing Logger Framework..." >> "$OUTPUT_FILE_WITH_LOGGER"
echo "PROMPT This installs the Oracle Logger framework for debugging and monitoring" >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/dependencies/logger_3.1.1/logger_install.sql" "Oracle Logger Framework Installation" "$OUTPUT_FILE_WITH_LOGGER"

# Then add all the UC AI content
echo "PROMPT Installing UC AI Framework Tables..." >> "$OUTPUT_FILE_WITH_LOGGER"
echo "PROMPT This creates the core database tables for message storage and configuration" >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/tables/install.sql" "UC AI Framework Tables" "$OUTPUT_FILE_WITH_LOGGER"

# Install triggers if they exist
if [ -f "$SRC_DIR/triggers/triggers.sql" ]; then
    echo "PROMPT Installing database triggers..." >> "$OUTPUT_FILE_WITH_LOGGER"
    echo "PROMPT This sets up automatic data validation and logging triggers" >> "$OUTPUT_FILE_WITH_LOGGER"
    add_file_content "$SRC_DIR/triggers/triggers.sql" "Database Triggers" "$OUTPUT_FILE_WITH_LOGGER"
fi

echo "PROMPT Installing PL/SQL packages..." >> "$OUTPUT_FILE_WITH_LOGGER"
echo "PROMPT This includes all AI provider packages and utility functions" >> "$OUTPUT_FILE_WITH_LOGGER"

# Install package specifications first (in dependency order)
echo "" >> "$OUTPUT_FILE_WITH_LOGGER"
echo "PROMPT Installing package specifications (headers)..." >> "$OUTPUT_FILE_WITH_LOGGER"

# 1. Core types package first (uc_ai.pks contains the main types)
echo "PROMPT - Installing core types and constants..." >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/packages/uc_ai.pks" "Core UC AI Package Specification - Types and Constants" "$OUTPUT_FILE_WITH_LOGGER"

# 2. Dependencies
echo "PROMPT - Installing utility functions..." >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/dependencies/key_function.sql" "Utility Functions" "$OUTPUT_FILE_WITH_LOGGER"

# 3. API packages (tools and message APIs)
echo "PROMPT - Installing API package specifications..." >> "$OUTPUT_FILE_WITH_LOGGER"
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    if [ -f "$SRC_DIR/packages/${api_pkg}.pks" ]; then
        case "$api_pkg" in
            "uc_ai_tools_api")
                add_file_content "$SRC_DIR/packages/${api_pkg}.pks" "Tools API Package Specification" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
            "uc_ai_message_api")
                add_file_content "$SRC_DIR/packages/${api_pkg}.pks" "Message API Package Specification" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
        esac
    fi
done

# 4. Provider packages (alphabetical order)
echo "PROMPT - Installing AI provider package specifications..." >> "$OUTPUT_FILE_WITH_LOGGER"
for provider_pks in "$SRC_DIR/packages/"*anthropic*.pks "$SRC_DIR/packages/"*google*.pks "$SRC_DIR/packages/"*openai*.pks; do
    if [ -f "$provider_pks" ]; then
        provider_file=$(basename "$provider_pks")
        case "$provider_file" in
            *anthropic*)
                add_file_content "$provider_pks" "Anthropic AI Provider Package Specification" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
            *google*)
                add_file_content "$provider_pks" "Google Gemini AI Provider Package Specification" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
            *openai*)
                add_file_content "$provider_pks" "OpenAI Provider Package Specification" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
        esac
    fi
done

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE_WITH_LOGGER"

# API packages first
echo "PROMPT - Installing API package bodies..." >> "$OUTPUT_FILE_WITH_LOGGER"
for api_pkg in "uc_ai_tools_api" "uc_ai_message_api"; do
    if [ -f "$SRC_DIR/packages/${api_pkg}.pkb" ]; then
        case "$api_pkg" in
            "uc_ai_tools_api")
                add_file_content "$SRC_DIR/packages/${api_pkg}.pkb" "Tools API Package Body - Implementation" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
            "uc_ai_message_api")
                add_file_content "$SRC_DIR/packages/${api_pkg}.pkb" "Message API Package Body - Implementation" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
        esac
    fi
done

# Provider packages
echo "PROMPT - Installing AI provider package bodies..." >> "$OUTPUT_FILE_WITH_LOGGER"
for provider_pkb in "$SRC_DIR/packages/"*anthropic*.pkb "$SRC_DIR/packages/"*google*.pkb "$SRC_DIR/packages/"*openai*.pkb; do
    if [ -f "$provider_pkb" ]; then
        provider_file=$(basename "$provider_pkb")
        case "$provider_file" in
            *anthropic*)
                add_file_content "$provider_pkb" "Anthropic AI Provider Package Body - Implementation" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
            *google*)
                add_file_content "$provider_pkb" "Google Gemini AI Provider Package Body - Implementation" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
            *openai*)
                add_file_content "$provider_pkb" "OpenAI Provider Package Body - Implementation" "$OUTPUT_FILE_WITH_LOGGER"
                ;;
        esac
    fi
done

# Core package body last (depends on others)
echo "PROMPT - Installing core UC AI package body..." >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/packages/uc_ai.pkb" "Core UC AI Package Body - Main Implementation" "$OUTPUT_FILE_WITH_LOGGER"

# Final completion message for logger version
cat >> "$OUTPUT_FILE_WITH_LOGGER" << 'EOF'

PROMPT ===================================================
PROMPT UC AI Framework with Logger installation complete!
PROMPT
PROMPT Installed components:
PROMPT - Oracle Logger Framework (for debugging and monitoring)
PROMPT - UC AI Framework with all providers
PROMPT
PROMPT Available AI providers:
PROMPT - OpenAI GPT models
PROMPT - Anthropic Claude models  
PROMPT - Google Gemini models
PROMPT
PROMPT Use uc_ai.generate_text() to start generating AI responses
PROMPT Use logger.log() for debugging and monitoring
PROMPT ===================================================
EOF

echo "Generated install_uc_ai_complete_with_logger.sql successfully!"
echo "Logger version output file: $OUTPUT_FILE_WITH_LOGGER"
