-- ============================================================================
-- UC AI Framework Uninstall Script
-- ============================================================================
-- Description: Complete removal of UC AI Framework
-- Version: 1.0
-- Repository: https://github.com/United-Codes/uc_ai
-- ============================================================================

SET ECHO ON
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

PROMPT Dropping core UC AI package...
DROP PACKAGE uc_ai;

PROMPT Dropping AI provider packages...
DROP PACKAGE uc_ai_openai;
DROP PACKAGE uc_ai_ollama;
DROP PACKAGE uc_ai_oci;
DROP PACKAGE uc_ai_google;
DROP PACKAGE uc_ai_anthropic;

PROMPT Dropping API packages...
DROP PACKAGE uc_ai_structured_output;
DROP PACKAGE uc_ai_message_api;
DROP PACKAGE uc_ai_tools_api;

PROMPT Packages dropped successfully.

-- ============================================================================
-- 2. DROP FUNCTIONS (Standalone)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 2: Dropping Standalone Functions...
PROMPT ===================================================

PROMPT Dropping key_function...
DROP FUNCTION key_function;

PROMPT Functions dropped successfully.

-- ============================================================================
-- 3. DROP TRIGGERS
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 3: Dropping Database Triggers...
PROMPT ===================================================

-- Drop triggers from triggers.sql
BEGIN
    FOR rec IN (
        SELECT trigger_name
        FROM user_triggers
        WHERE table_name IN ('UC_AI_TOOLS', 'UC_AI_CATEGORIES', 'UC_AI_TOOL_PARAMETERS', 'UC_AI_TOOL_CATEGORIES')
        OR trigger_name LIKE 'UC_AI%'
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TRIGGER ' || rec.trigger_name;
        DBMS_OUTPUT.PUT_LINE('Dropped trigger: ' || rec.trigger_name);
    END LOOP;
END;
/

PROMPT Triggers dropped successfully.

-- ============================================================================
-- 4. DROP TABLES (Drop dependent tables first)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 4: Dropping Tables...
PROMPT ===================================================

PROMPT Dropping junction/dependent tables first...
DROP TABLE uc_ai_tool_categories CASCADE CONSTRAINTS;
PROMPT - Dropped: uc_ai_tool_categories

PROMPT Dropping parameter tables...
DROP TABLE uc_ai_tool_parameters CASCADE CONSTRAINTS;
PROMPT - Dropped: uc_ai_tool_parameters

PROMPT Dropping tools table...
DROP TABLE uc_ai_tools CASCADE CONSTRAINTS;
PROMPT - Dropped: uc_ai_tools

PROMPT Dropping categories table...
DROP TABLE uc_ai_categories CASCADE CONSTRAINTS;
PROMPT - Dropped: uc_ai_categories

PROMPT Tables dropped successfully.

-- ============================================================================
-- 5. DROP SEQUENCES
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 5: Dropping Sequences...
PROMPT ===================================================

DROP SEQUENCE uc_ai_tool_categories_seq;
PROMPT - Dropped: uc_ai_tool_categories_seq

DROP SEQUENCE uc_ai_tool_parameters_seq;
PROMPT - Dropped: uc_ai_tool_parameters_seq

DROP SEQUENCE uc_ai_tools_seq;
PROMPT - Dropped: uc_ai_tools_seq

DROP SEQUENCE uc_ai_categories_seq;
PROMPT - Dropped: uc_ai_categories_seq

PROMPT Sequences dropped successfully.

-- ============================================================================
-- 6. VERIFY CLEANUP
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 6: Verification - Checking for Remaining Objects...
PROMPT ===================================================

DECLARE
    v_count NUMBER := 0;
BEGIN
    -- Check for remaining UC AI objects
    SELECT COUNT(*)
    INTO v_count
    FROM user_objects
    WHERE (
        object_name IN (
            'UC_AI',
            'UC_AI_ANTHROPIC',
            'UC_AI_GOOGLE',
            'UC_AI_OCI',
            'UC_AI_OLLAMA',
            'UC_AI_OPENAI',
            'UC_AI_MESSAGE_API',
            'UC_AI_TOOLS_API',
            'UC_AI_STRUCTURED_OUTPUT',
            'KEY_FUNCTION'
        )
        OR object_name IN (
            'UC_AI_CATEGORIES',
            'UC_AI_TOOLS',
            'UC_AI_TOOL_PARAMETERS',
            'UC_AI_TOOL_CATEGORIES'
        )
        OR object_name IN (
            'UC_AI_CATEGORIES_SEQ',
            'UC_AI_TOOLS_SEQ',
            'UC_AI_TOOL_PARAMETERS_SEQ',
            'UC_AI_TOOL_CATEGORIES_SEQ'
        )
    )
    AND object_type NOT IN ('LOB', 'INDEX');  -- Exclude auto-created objects
    
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('WARNING: ' || v_count || ' UC AI objects still exist:');
        DBMS_OUTPUT.PUT_LINE('');
        
        FOR rec IN (
            SELECT object_type, object_name, status
            FROM user_objects
            WHERE (
                object_name IN (
                    'UC_AI',
                    'UC_AI_ANTHROPIC',
                    'UC_AI_GOOGLE',
                    'UC_AI_OCI',
                    'UC_AI_OLLAMA',
                    'UC_AI_OPENAI',
                    'UC_AI_MESSAGE_API',
                    'UC_AI_TOOLS_API',
                    'UC_AI_STRUCTURED_OUTPUT',
                    'KEY_FUNCTION',
                    'UC_AI_CATEGORIES',
                    'UC_AI_TOOLS',
                    'UC_AI_TOOL_PARAMETERS',
                    'UC_AI_TOOL_CATEGORIES',
                    'UC_AI_CATEGORIES_SEQ',
                    'UC_AI_TOOLS_SEQ',
                    'UC_AI_TOOL_PARAMETERS_SEQ',
                    'UC_AI_TOOL_CATEGORIES_SEQ'
                )
            )
            AND object_type NOT IN ('LOB', 'INDEX')
            ORDER BY object_type, object_name
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  ' || RPAD(rec.object_type, 20) || ' ' || 
                               RPAD(rec.object_name, 40) || ' ' || rec.status);
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('You may need to manually drop these objects.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('SUCCESS: All UC AI Framework objects have been removed.');
    END IF;
END;
/

-- ============================================================================
-- 7. PURGE RECYCLEBIN (Optional)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 7: Purging Recyclebin...
PROMPT ===================================================

PURGE RECYCLEBIN;
PROMPT Recyclebin purged.

-- ============================================================================
-- SUMMARY
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT UC AI Framework Uninstallation Complete!
PROMPT ===================================================
PROMPT
PROMPT Summary of removed objects:
PROMPT
PROMPT Packages:
PROMPT   - uc_ai
PROMPT   - uc_ai_anthropic
PROMPT   - uc_ai_google
PROMPT   - uc_ai_oci
PROMPT   - uc_ai_ollama
PROMPT   - uc_ai_openai
PROMPT   - uc_ai_message_api
PROMPT   - uc_ai_tools_api
PROMPT   - uc_ai_structured_output
PROMPT
PROMPT Functions:
PROMPT   - key_function
PROMPT
PROMPT Tables:
PROMPT   - uc_ai_categories
PROMPT   - uc_ai_tools
PROMPT   - uc_ai_tool_parameters
PROMPT   - uc_ai_tool_categories
PROMPT
PROMPT Sequences:
PROMPT   - uc_ai_categories_seq
PROMPT   - uc_ai_tools_seq
PROMPT   - uc_ai_tool_parameters_seq
PROMPT   - uc_ai_tool_categories_seq
PROMPT
PROMPT Triggers:
PROMPT   - All triggers on UC AI tables
PROMPT
PROMPT For more information, visit:
PROMPT https://github.com/United-Codes/uc_ai
PROMPT ===================================================

SPOOL OFF

SET ECHO OFF
SET FEEDBACK ON
SET VERIFY ON

-- End of uninstall script
