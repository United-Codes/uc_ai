#!/bin/bash

# Script to generate upgrade_uc_ai.sql, the single upgrade script for every
# release from v25.7 on. It is safe to run more than once: the schema step checks
# the data dictionary before each change, and everything else is create or replace.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared package utilities
source "$SCRIPT_DIR/package_utils.sh"

ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="${ROOT_DIR}/upgrade_uc_ai.sql"
SRC_DIR=$(get_src_dir "$SCRIPT_DIR")

# Validate src directory exists
if ! validate_src_dir "$SRC_DIR"; then
    exit 1
fi

echo "Generating upgrade_uc_ai.sql with inlined content..."

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
-- UC AI Framework Upgrade Script
-- Self-contained: all contents are inlined.
-- Upgrades any UC AI installation from v25.7 or later to this release.
-- Safe to run more than once. Each schema change checks the data dictionary first.
-- The script stops at the first failed schema step, and fails at the end when
-- an object of a fresh install is missing.
--
-- It can be called from another script: it does not exit, and it leaves
-- "whenever sqlerror exit failure rollback", serveroutput and sqlblanklines on.

set serveroutput on size unlimited
set sqlblanklines on
whenever sqlerror exit failure rollback

PROMPT ===================================================
PROMPT UC AI Framework Upgrade Starting...
PROMPT ===================================================

PROMPT This script will upgrade the following components:
PROMPT - Tables, sequences, constraints and indexes (only what is missing)
PROMPT - Comments and triggers
PROMPT - Core UC AI package and all provider packages
PROMPT - API packages (tools and message APIs)
PROMPT - Utility functions
PROMPT - Reporting views
PROMPT - Verification against a fresh install
PROMPT ===================================================

PROMPT Upgrading tables, sequences, constraints and indexes...
EOF

# Schema changes: guarded by data dictionary checks (src/upgrade/upgrade_schema.sql)
if [ ! -f "$SRC_DIR/upgrade/upgrade_schema.sql" ]; then
    echo "Error: $SRC_DIR/upgrade/upgrade_schema.sql not found"
    exit 1
fi
add_file_content "$SRC_DIR/upgrade/upgrade_schema.sql" "Schema upgrade (checked, re-runnable)"

# Comments: the single-line "comment on" statements of the table script. They
# are idempotent, so they are taken from there and need no copy to keep in sync.
if [ -f "$SRC_DIR/tables/install.sql" ]; then
    {
        echo ""
        echo "-- ===================================================="
        echo "-- Table and column comments"
        echo "-- File: install.sql (comment on statements)"
        echo "-- ===================================================="
        echo ""
        echo "PROMPT Setting table and column comments..."
        grep -E '^comment on ' "$SRC_DIR/tables/install.sql"
        echo ""
    } >> "$OUTPUT_FILE"
fi

# Triggers are create or replace. They need the columns of the schema step.
if [ -f "$SRC_DIR/triggers/triggers.sql" ]; then
    echo "PROMPT Recreating database triggers..." >> "$OUTPUT_FILE"
    add_file_content "$SRC_DIR/triggers/triggers.sql" "Database Triggers"
fi

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

# Recreate the views (create or replace, so a changed definition ships with the
# upgrade). They need the tables of the schema step.
if [ -f "$SRC_DIR/views/views.sql" ]; then
    echo "PROMPT Recreating database views..." >> "$OUTPUT_FILE"
    add_file_content "$SRC_DIR/views/views.sql" "Database Views"
fi

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

# Verify phase: every object of a fresh install exists. The expected objects
# come from install.sql, so a DDL change without a guarded step fails here. The
# markers let scripts/test_upgrade.sh run the phase on its own.
VERIFY_TEMPLATE="$SRC_DIR/upgrade/verify_schema.sql"
if [ ! -f "$VERIFY_TEMPLATE" ]; then
    echo "Error: $VERIFY_TEMPLATE not found"
    exit 1
fi
EXPECTED_OBJECTS=$(awk -f "$SCRIPT_DIR/list_install_objects.awk" "$SRC_DIR/tables/install.sql" \
    | sort -u | sed "s/.*/    '&',/" | sed '$ s/,$//')
if [ -z "$EXPECTED_OBJECTS" ]; then
    echo "Error: found no objects in $SRC_DIR/tables/install.sql"
    exit 1
fi
{
    echo ""
    echo "PROMPT Verifying the schema against a fresh install..."
    echo "-- VERIFY START"
    while IFS= read -r line; do
        if [ "$line" = "    -- @EXPECTED_OBJECTS@" ]; then
            printf '%s\n' "$EXPECTED_OBJECTS"
        else
            printf '%s\n' "$line"
        fi
    done < "$VERIFY_TEMPLATE"
    echo "-- VERIFY END"
} >> "$OUTPUT_FILE"

# Final completion message. The script does not reset "whenever sqlerror": a
# calling script (for example the APEX Document Management upgrade) keeps the
# stop-on-failure behavior, and sets its own again after the call if it wants
# another one.
cat >> "$OUTPUT_FILE" << 'EOF'

PROMPT ===================================================
PROMPT UC AI upgrade complete!
PROMPT Refer to the documentation for usage instructions: https://www.united-codes.com/products/uc-ai/docs/
PROMPT ===================================================
EOF

echo "Generated upgrade_uc_ai.sql successfully!"
echo ""
echo "Upgrade script created with the following components:"

# Show what was included using the shared utility
list_installed_packages "$SRC_DIR" true

echo ""
echo "This script is ideal for:"
echo "- Upgrading any UC AI installation from v25.7 on"
echo "- Running again on an installation that is already up to date"
echo "- Healing a schema that holds a half-applied older migration"
echo ""
echo "Output file: $OUTPUT_FILE"
