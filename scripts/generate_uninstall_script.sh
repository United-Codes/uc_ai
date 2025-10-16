#!/bin/bash

# Script to generate uninstall.sql by scanning the src directory structure
# This ensures all objects are dropped in the correct reverse order

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared package utilities
source "$SCRIPT_DIR/package_utils.sh"

OUTPUT_FILE="${SCRIPT_DIR}/../uninstall.sql"
SRC_DIR=$(get_src_dir "$SCRIPT_DIR")

# Validate src directory exists
if ! validate_src_dir "$SRC_DIR"; then
    exit 1
fi

echo "Generating uninstall.sql..."

# Start writing the uninstall script
cat > "$OUTPUT_FILE" << 'EOF'
-- ============================================================================
-- UC AI Framework Uninstall Script
-- ============================================================================
-- Description: Complete removal of UC AI Framework
-- Repository: https://github.com/United-Codes/uc_ai
-- ============================================================================

-- @dblinter ignore(G-5010, G-6010, G-2330, G-4140)

SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF

-- Spool output to log file
SPOOL uc_ai_uninstall.log

PROMPT ===================================================
PROMPT UC AI Framework Uninstallation Starting...
PROMPT ===================================================
PROMPT
PROMPT WARNING: This will remove all UC AI Framework objects
PROMPT Press Ctrl+C to cancel or Enter to continue...
PAUSE

-- ============================================================================
-- 1. DROP PACKAGES (Reverse order from installation)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 1: Dropping PL/SQL Packages...
PROMPT ===================================================

EOF

# Drop packages in reverse order
# Core package body first (was installed last)
echo "PROMPT Dropping core UC AI package..." >> "$OUTPUT_FILE"
while IFS= read -r body_file; do
    if is_core_package "$(basename "$body_file")"; then
        package_name=$(basename "$body_file" .pkb)
        echo "DROP PACKAGE ${package_name};" >> "$OUTPUT_FILE"
        break
    fi
done < <(get_package_bodies_ordered "$SRC_DIR")

echo "" >> "$OUTPUT_FILE"

# Provider packages
echo "PROMPT Dropping AI provider packages..." >> "$OUTPUT_FILE"
# Reverse the provider packages array
declare -a PROVIDER_PACKAGES_REV=()
for ((i=${#PROVIDER_PACKAGES[@]}-1; i>=0; i--)); do
    PROVIDER_PACKAGES_REV+=("${PROVIDER_PACKAGES[$i]}")
done

for provider_pkg in "${PROVIDER_PACKAGES_REV[@]}"; do
    if [ -f "$SRC_DIR/packages/${provider_pkg}.pkb" ] || [ -f "$SRC_DIR/packages/${provider_pkg}.pks" ]; then
        echo "DROP PACKAGE ${provider_pkg};" >> "$OUTPUT_FILE"
    fi
done

echo "" >> "$OUTPUT_FILE"

# API packages (reverse order)
echo "PROMPT Dropping API packages..." >> "$OUTPUT_FILE"
declare -a API_PACKAGES_REV=()
for ((i=${#API_PACKAGES[@]}-1; i>=0; i--)); do
    API_PACKAGES_REV+=("${API_PACKAGES[$i]}")
done

for api_pkg in "${API_PACKAGES_REV[@]}"; do
    if [ -f "$SRC_DIR/packages/${api_pkg}.pkb" ] || [ -f "$SRC_DIR/packages/${api_pkg}.pks" ]; then
        echo "DROP PACKAGE ${api_pkg};" >> "$OUTPUT_FILE"
    fi
done

echo "" >> "$OUTPUT_FILE"
echo "PROMPT Packages dropped successfully." >> "$OUTPUT_FILE"

# Drop dependencies
cat >> "$OUTPUT_FILE" << 'EOF'

-- ============================================================================
-- 2. DROP FUNCTIONS (Standalone)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 2: Dropping Standalone Functions...
PROMPT ===================================================

EOF

echo "PROMPT Dropping UC_AI_GET_KEY function..." >> "$OUTPUT_FILE"
echo "DROP FUNCTION UC_AI_GET_KEY;" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"


echo "PROMPT Functions dropped successfully." >> "$OUTPUT_FILE"

# Drop triggers
cat >> "$OUTPUT_FILE" << 'EOF'

-- ============================================================================
-- 3. DROP TRIGGERS
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 3: Dropping Database Triggers...
PROMPT ===================================================

BEGIN
    <<triggers_loop>>
    FOR rec IN (
        SELECT trigger_name
        FROM user_triggers
        WHERE table_name IN ('UC_AI_TOOLS', 'UC_AI_CATEGORIES', 'UC_AI_TOOL_PARAMETERS', 'UC_AI_TOOL_CATEGORIES')
        OR trigger_name LIKE 'UC_AI%'
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TRIGGER ' || rec.trigger_name;
        sys.dbms_output.put_line('Dropped trigger: ' || rec.trigger_name);
    END LOOP triggers_loop;
END;
/

PROMPT Triggers dropped successfully.

EOF

# Drop tables - need to scan tables/install.sql to find what tables exist
if [ -f "$SRC_DIR/tables/install.sql" ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
-- ============================================================================
-- 4. DROP TABLES (Drop dependent tables first)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 4: Dropping Tables...
PROMPT ===================================================

BEGIN
    -- Drop tables in reverse order with CASCADE CONSTRAINTS
    <<tables_loop>>
    FOR rec IN (
        SELECT table_name
        FROM user_tables
        WHERE table_name LIKE 'UC_AI%'
        ORDER BY table_name DESC
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || rec.table_name || ' CASCADE CONSTRAINTS';
        sys.dbms_output.put_line('Dropped table: ' || rec.table_name);
    END LOOP tables_loop;
    
    IF SQL%ROWCOUNT = 0 THEN
        sys.dbms_output.put_line('No UC AI tables found.');
    END IF;
END;
/

PROMPT Tables dropped successfully.

EOF
fi

# Drop sequences
cat >> "$OUTPUT_FILE" << 'EOF'
-- ============================================================================
-- 5. DROP SEQUENCES
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 5: Dropping Sequences...
PROMPT ===================================================

BEGIN
    <<sequences_loop>>
    FOR rec IN (
        SELECT sequence_name
        FROM user_sequences
        WHERE sequence_name LIKE 'UC_AI%'
        ORDER BY sequence_name
    ) LOOP
        EXECUTE IMMEDIATE 'DROP SEQUENCE ' || rec.sequence_name;
        sys.dbms_output.put_line('Dropped sequence: ' || rec.sequence_name);
    END LOOP sequences_loop;
    
    IF SQL%ROWCOUNT = 0 THEN
        sys.dbms_output.put_line('No UC AI sequences found.');
    END IF;
END;
/

PROMPT Sequences dropped successfully.

-- ============================================================================
-- 6. VERIFY CLEANUP
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 6: Verification - Checking for Remaining Objects...
PROMPT ===================================================

DECLARE
    l_count NUMBER := 0;
BEGIN
    -- Check for remaining UC AI objects
    SELECT COUNT(*)
    INTO l_count
    FROM user_objects
    WHERE object_name LIKE 'UC_AI%'
    OR object_name = 'UC_AI_GET_KEY'
    AND object_type NOT IN ('LOB', 'INDEX');  -- Exclude auto-created objects
    
    IF l_count > 0 THEN
        sys.dbms_output.put_line('WARNING: ' || l_count || ' UC AI objects still exist:');
        sys.dbms_output.put_line('');
        
        <<remaining_objects_loop>>
        FOR rec IN (
            SELECT object_type, object_name, status
            FROM user_objects
            WHERE (object_name LIKE 'UC_AI%' OR object_name = 'UC_AI_GET_KEY')
            AND object_type NOT IN ('LOB', 'INDEX')
            ORDER BY object_type, object_name
        ) LOOP
            sys.dbms_output.put_line('  ' || RPAD(rec.object_type, 20) || ' ' || 
                               RPAD(rec.object_name, 40) || ' ' || rec.status);
        END LOOP remaining_objects_loop;
        
        sys.dbms_output.put_line('');
        sys.dbms_output.put_line('You may need to manually drop these objects.');
    ELSE
        sys.dbms_output.put_line('SUCCESS: All UC AI Framework objects have been removed.');
    END IF;
END;
/

-- ============================================================================
-- SUMMARY
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT UC AI Framework Uninstallation Complete!
PROMPT ===================================================
PROMPT
PROMPT The following object types have been removed:
PROMPT
PROMPT - All UC AI packages (core, API, and provider packages)
PROMPT - Standalone functions (UC_AI_GET_KEY)
PROMPT - Database triggers on UC AI tables
PROMPT - All UC AI tables
PROMPT - All UC AI sequences
PROMPT
PROMPT For more information, visit:
PROMPT https://github.com/United-Codes/uc_ai
PROMPT https://www.united-codes.com/products/uc-ai/docs/
PROMPT ===================================================

SPOOL OFF

SET ECHO OFF
SET FEEDBACK ON
SET VERIFY ON

-- End of uninstall script

EOF

echo "Generated uninstall.sql successfully!"
echo ""
echo "Objects to be dropped (in order):"
echo ""
echo "1. Packages (reverse installation order):"

# Core package
while IFS= read -r body_file; do
    if is_core_package "$(basename "$body_file")"; then
        package_name=$(basename "$body_file" .pkb)
        echo "   - ${package_name} (Core)"
        break
    fi
done < <(get_package_bodies_ordered "$SRC_DIR")

# Provider packages (reversed)
for provider_pkg in "${PROVIDER_PACKAGES_REV[@]}"; do
    if [ -f "$SRC_DIR/packages/${provider_pkg}.pkb" ] || [ -f "$SRC_DIR/packages/${provider_pkg}.pks" ]; then
        echo "   - ${provider_pkg} (Provider)"
    fi
done

# API packages (reversed)
for api_pkg in "${API_PACKAGES_REV[@]}"; do
    if [ -f "$SRC_DIR/packages/${api_pkg}.pkb" ] || [ -f "$SRC_DIR/packages/${api_pkg}.pks" ]; then
        echo "   - ${api_pkg} (API)"
    fi
done

echo ""
echo "2. Standalone Functions:"
echo "   - UC_AI_GET_KEY"


echo ""
echo "3. Triggers:"
echo "   - All triggers on UC AI tables"

echo ""
echo "4. Tables:"
echo "   - All UC_AI* tables (dynamic detection)"

echo ""
echo "5. Sequences:"
echo "   - All UC_AI* sequences (dynamic detection)"

echo ""
echo "Uninstall order ensures proper dependency cleanup."
