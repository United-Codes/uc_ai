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
-- UC AI Installation Script

PROMPT ===================================================
PROMPT UC AI Installation Starting...
PROMPT ===================================================

EOF

# Install tables first
echo "PROMPT Installing UC AI Tables..." >> "$OUTPUT_FILE"
echo "PROMPT This creates the core database tables for message storage and configuration" >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/tables/install.sql" "UC AI Tables"

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
add_file_content "$SRC_DIR/packages/uc_ai.pks" "Core UC AI Package Specification - uc_ai.pks"

# 2. Dependencies
echo "PROMPT - Installing utility functions..." >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/dependencies/key_function.sql" "Utility Functions"

# 3. API packages (tools and message APIs)
echo "PROMPT - Installing API package specifications..." >> "$OUTPUT_FILE"
for pks_file in "$SRC_DIR/packages/"*_api.pks; do
    if [ -f "$pks_file" ]; then
        filename=$(basename "$pks_file")
        add_file_content "$pks_file" "API Package Specification - $filename"
    fi
done

# 4. Provider packages (all other .pks files except uc_ai.pks and API packages)
echo "PROMPT - Installing AI provider package specifications..." >> "$OUTPUT_FILE"
for pks_file in "$SRC_DIR/packages/"*.pks; do
    filename=$(basename "$pks_file")
    # Skip uc_ai.pks (already installed) and API packages (already installed)
    if [[ "$filename" != "uc_ai.pks" && "$filename" != *"_api.pks" ]]; then
        add_file_content "$pks_file" "Provider Package Specification - $filename"
    fi
done

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE"

# API packages first
echo "PROMPT - Installing API package bodies..." >> "$OUTPUT_FILE"
for pkb_file in "$SRC_DIR/packages/"*_api.pkb; do
    if [ -f "$pkb_file" ]; then
        filename=$(basename "$pkb_file")
        add_file_content "$pkb_file" "API Package Body - $filename"
    fi
done

# Provider packages
echo "PROMPT - Installing AI provider package bodies..." >> "$OUTPUT_FILE"
for pkb_file in "$SRC_DIR/packages/"*.pkb; do
    filename=$(basename "$pkb_file")
    # Skip uc_ai.pkb (installed last) and API packages (already installed)
    if [[ "$filename" != "uc_ai.pkb" && "$filename" != *"_api.pkb" ]]; then
        add_file_content "$pkb_file" "Provider Package Body - $filename"
    fi
done

# Core package body last (depends on others)
echo "PROMPT - Installing core UC AI package body..." >> "$OUTPUT_FILE"
add_file_content "$SRC_DIR/packages/uc_ai.pkb" "Core UC AI Package Body - uc_ai.pkb"

# Final completion message
cat >> "$OUTPUT_FILE" << 'EOF'

PROMPT ===================================================
PROMPT UC AI installation complete!
PROMPT Refer to the documentation for usage instructions: https://www.united-codes.com/products/uc-ai/docs/
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
for pks_file in "$SRC_DIR/packages/"*_api.pks; do
    if [ -f "$pks_file" ]; then
        echo "  ✓ src/packages/$(basename "$pks_file")"
    fi
done
for pks_file in "$SRC_DIR/packages/"*.pks; do
    filename=$(basename "$pks_file")
    if [[ "$filename" != "uc_ai.pks" && "$filename" != *"_api.pks" ]]; then
        echo "  ✓ src/packages/$filename"
    fi
done

echo "Package bodies:"
for pkb_file in "$SRC_DIR/packages/"*_api.pkb; do
    if [ -f "$pkb_file" ]; then
        echo "  ✓ src/packages/$(basename "$pkb_file")"
    fi
done
for pkb_file in "$SRC_DIR/packages/"*.pkb; do
    filename=$(basename "$pkb_file")
    if [[ "$filename" != "uc_ai.pkb" && "$filename" != *"_api.pkb" ]]; then
        echo "  ✓ src/packages/$filename"
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
-- UC AI Installation Script with Logger

PROMPT ===================================================
PROMPT UC AI Installation with Logger Starting...
PROMPT ===================================================

EOF

# First install the logger
echo "PROMPT Installing Logger..." >> "$OUTPUT_FILE_WITH_LOGGER"
echo "PROMPT This installs the Oracle Logger framework for debugging and monitoring" >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/dependencies/logger_3.1.1/logger_install.sql" "Oracle Logger Installation" "$OUTPUT_FILE_WITH_LOGGER"

# Then add all the UC AI content
echo "PROMPT Installing UC AI Tables..." >> "$OUTPUT_FILE_WITH_LOGGER"
echo "PROMPT This creates the core database tables for message storage and configuration" >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/tables/install.sql" "UC AI Tables" "$OUTPUT_FILE_WITH_LOGGER"

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
add_file_content "$SRC_DIR/packages/uc_ai.pks" "Core UC AI Package Specification - uc_ai.pks" "$OUTPUT_FILE_WITH_LOGGER"

# 2. Dependencies
echo "PROMPT - Installing utility functions..." >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/dependencies/key_function.sql" "Utility Functions" "$OUTPUT_FILE_WITH_LOGGER"

# 3. API packages (tools and message APIs)
echo "PROMPT - Installing API package specifications..." >> "$OUTPUT_FILE_WITH_LOGGER"
for pks_file in "$SRC_DIR/packages/"*_api.pks; do
    if [ -f "$pks_file" ]; then
        filename=$(basename "$pks_file")
        add_file_content "$pks_file" "API Package Specification - $filename" "$OUTPUT_FILE_WITH_LOGGER"
    fi
done

# 4. Provider packages (all other .pks files except uc_ai.pks and API packages)
echo "PROMPT - Installing AI provider package specifications..." >> "$OUTPUT_FILE_WITH_LOGGER"
for pks_file in "$SRC_DIR/packages/"*.pks; do
    filename=$(basename "$pks_file")
    # Skip uc_ai.pks (already installed) and API packages (already installed)
    if [[ "$filename" != "uc_ai.pks" && "$filename" != *"_api.pks" ]]; then
        add_file_content "$pks_file" "Provider Package Specification - $filename" "$OUTPUT_FILE_WITH_LOGGER"
    fi
done

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE_WITH_LOGGER"

# API packages first
echo "PROMPT - Installing API package bodies..." >> "$OUTPUT_FILE_WITH_LOGGER"
for pkb_file in "$SRC_DIR/packages/"*_api.pkb; do
    if [ -f "$pkb_file" ]; then
        filename=$(basename "$pkb_file")
        add_file_content "$pkb_file" "API Package Body - $filename" "$OUTPUT_FILE_WITH_LOGGER"
    fi
done

# Provider packages
echo "PROMPT - Installing AI provider package bodies..." >> "$OUTPUT_FILE_WITH_LOGGER"
for pkb_file in "$SRC_DIR/packages/"*.pkb; do
    filename=$(basename "$pkb_file")
    # Skip uc_ai.pkb (installed last) and API packages (already installed)
    if [[ "$filename" != "uc_ai.pkb" && "$filename" != *"_api.pkb" ]]; then
        add_file_content "$pkb_file" "Provider Package Body - $filename" "$OUTPUT_FILE_WITH_LOGGER"
    fi
done

# Core package body last (depends on others)
echo "PROMPT - Installing core UC AI package body..." >> "$OUTPUT_FILE_WITH_LOGGER"
add_file_content "$SRC_DIR/packages/uc_ai.pkb" "Core UC AI Package Body - uc_ai.pkb" "$OUTPUT_FILE_WITH_LOGGER"

# Final completion message for logger version
cat >> "$OUTPUT_FILE_WITH_LOGGER" << 'EOF'

PROMPT ===================================================
PROMPT UC AI with Logger installation complete!
PROMPT Refer to the documentation for usage instructions: https://www.united-codes.com/products/uc-ai/docs/
PROMPT ===================================================
EOF

echo "Generated install_uc_ai_complete_with_logger.sql successfully!"
echo "Logger version output file: $OUTPUT_FILE_WITH_LOGGER"

echo ""
echo "Generating install_uc_ai_complete_with_logger_noop.sql with no-op logger..."

# Generate the complete script with no-op logger
OUTPUT_FILE_WITH_LOGGER_NOOP="${ROOT_DIR}/install_uc_ai_complete_with_logger_noop.sql"

# Start writing the install script with no-op logger
cat > "$OUTPUT_FILE_WITH_LOGGER_NOOP" << 'EOF'
-- UC AI Installation Script with No-Op Logger Framework

PROMPT ===================================================
PROMPT UC AI with No-Op Logger Installation Starting...
PROMPT ===================================================

EOF

# First install the no-op logger
echo "PROMPT Installing No-Op Logger Framework..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
echo "PROMPT This installs the Oracle Logger no-op version (same API, no actual logging)" >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
add_file_content "$SRC_DIR/dependencies/logger_3.1.1/logger_no_op.sql" "Oracle Logger No-Op Framework Installation" "$OUTPUT_FILE_WITH_LOGGER_NOOP"

# Then add all the UC AI content
echo "PROMPT Installing UC AI Tables..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
echo "PROMPT This creates the core database tables for message storage and configuration" >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
add_file_content "$SRC_DIR/tables/install.sql" "UC AI Tables" "$OUTPUT_FILE_WITH_LOGGER_NOOP"

# Install triggers if they exist
if [ -f "$SRC_DIR/triggers/triggers.sql" ]; then
    echo "PROMPT Installing database triggers..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
    echo "PROMPT This sets up automatic data validation and logging triggers" >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
    add_file_content "$SRC_DIR/triggers/triggers.sql" "Database Triggers" "$OUTPUT_FILE_WITH_LOGGER_NOOP"
fi

echo "PROMPT Installing PL/SQL packages..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
echo "PROMPT This includes all AI provider packages and utility functions" >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"

# Install package specifications first (in dependency order)
echo "" >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
echo "PROMPT Installing package specifications (headers)..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"

# 1. Core types package first (uc_ai.pks contains the main types)
echo "PROMPT - Installing core types and constants..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
add_file_content "$SRC_DIR/packages/uc_ai.pks" "Core UC AI Package Specification - uc_ai.pks" "$OUTPUT_FILE_WITH_LOGGER_NOOP"

# 2. Dependencies
echo "PROMPT - Installing utility functions..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
add_file_content "$SRC_DIR/dependencies/key_function.sql" "Utility Functions" "$OUTPUT_FILE_WITH_LOGGER_NOOP"

# 3. API packages (tools and message APIs)
echo "PROMPT - Installing API package specifications..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
for pks_file in "$SRC_DIR/packages/"*_api.pks; do
    if [ -f "$pks_file" ]; then
        filename=$(basename "$pks_file")
        add_file_content "$pks_file" "API Package Specification - $filename" "$OUTPUT_FILE_WITH_LOGGER_NOOP"
    fi
done

# 4. Provider packages (all other .pks files except uc_ai.pks and API packages)
echo "PROMPT - Installing AI provider package specifications..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
for pks_file in "$SRC_DIR/packages/"*.pks; do
    filename=$(basename "$pks_file")
    # Skip uc_ai.pks (already installed) and API packages (already installed)
    if [[ "$filename" != "uc_ai.pks" && "$filename" != *"_api.pks" ]]; then
        add_file_content "$pks_file" "Provider Package Specification - $filename" "$OUTPUT_FILE_WITH_LOGGER_NOOP"
    fi
done

# Install package bodies (same order as specifications)
echo "PROMPT Installing package bodies (implementations)..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"

# API packages first
echo "PROMPT - Installing API package bodies..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
for pkb_file in "$SRC_DIR/packages/"*_api.pkb; do
    if [ -f "$pkb_file" ]; then
        filename=$(basename "$pkb_file")
        add_file_content "$pkb_file" "API Package Body - $filename" "$OUTPUT_FILE_WITH_LOGGER_NOOP"
    fi
done

# Provider packages
echo "PROMPT - Installing AI provider package bodies..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
for pkb_file in "$SRC_DIR/packages/"*.pkb; do
    filename=$(basename "$pkb_file")
    # Skip uc_ai.pkb (installed last) and API packages (already installed)
    if [[ "$filename" != "uc_ai.pkb" && "$filename" != *"_api.pkb" ]]; then
        add_file_content "$pkb_file" "Provider Package Body - $filename" "$OUTPUT_FILE_WITH_LOGGER_NOOP"
    fi
done

# Core package body last (depends on others)
echo "PROMPT - Installing core UC AI package body..." >> "$OUTPUT_FILE_WITH_LOGGER_NOOP"
add_file_content "$SRC_DIR/packages/uc_ai.pkb" "Core UC AI Package Body - uc_ai.pkb" "$OUTPUT_FILE_WITH_LOGGER_NOOP"

# Final completion message for no-op logger version
cat >> "$OUTPUT_FILE_WITH_LOGGER_NOOP" << 'EOF'

PROMPT ===================================================
PROMPT UC AI with No-Op Logger installation complete!
PROMPT 
PROMPT The no-op logger provides the same API as the full logger
PROMPT but does not actually write to any tables or create dependencies.
PROMPT This is useful for environments where logging is not needed
PROMPT or where you want to minimize database overhead.
PROMPT
PROMPT Refer to the documentation for usage instructions: https://www.united-codes.com/products/uc-ai/docs/
PROMPT ===================================================
EOF

echo "Generated install_uc_ai_complete_with_logger_noop.sql successfully!"
echo "No-op Logger version output file: $OUTPUT_FILE_WITH_LOGGER_NOOP"
