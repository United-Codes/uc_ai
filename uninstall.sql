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

PROMPT Dropping core UC AI package...
DROP PACKAGE uc_ai;

PROMPT Dropping AI provider packages...
DROP PACKAGE uc_ai_responses_api;
DROP PACKAGE uc_ai_openrouter;
DROP PACKAGE uc_ai_xai;
DROP PACKAGE uc_ai_openai;
DROP PACKAGE uc_ai_ollama;
DROP PACKAGE uc_ai_oci;
DROP PACKAGE uc_ai_mistral;
DROP PACKAGE uc_ai_google;
DROP PACKAGE uc_ai_anthropic;

PROMPT Dropping API packages...
DROP PACKAGE uc_ai_utils;
DROP PACKAGE uc_ai_agent_workflow_api;
DROP PACKAGE uc_ai_agent_exec_api;
DROP PACKAGE uc_ai_agents_api;
DROP PACKAGE uc_ai_toon;
DROP PACKAGE uc_ai_http;
DROP PACKAGE uc_ai_error;
DROP PACKAGE uc_ai_logger;
DROP PACKAGE uc_ai_structured_output;
DROP PACKAGE uc_ai_memory;
DROP PACKAGE uc_ai_prompt_profiles_api;
DROP PACKAGE uc_ai_message_api;
DROP PACKAGE uc_ai_tools_api;
DROP PACKAGE uc_ai_settings;

PROMPT Packages dropped successfully.

-- ============================================================================
-- 2. DROP FUNCTIONS (Standalone)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 2: Dropping Standalone Functions...
PROMPT ===================================================

PROMPT Dropping UC_AI_GET_KEY function...
DROP FUNCTION UC_AI_GET_KEY;

PROMPT Functions dropped successfully.

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
        -- All UC AI triggers are named uc_ai_*, so the name pattern finds them all.
        -- Do not also select by table_name: that dropped user-owned triggers on
        -- UC AI tables, and the frozen list went stale (UC_AI_TOOL_CATEGORIES was
        -- removed in v25.5).
        WHERE trigger_name LIKE 'UC_AI%'
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TRIGGER ' || rec.trigger_name;
        sys.dbms_output.put_line('Dropped trigger: ' || rec.trigger_name);
    END LOOP triggers_loop;
END;
/

PROMPT Triggers dropped successfully.

-- ============================================================================
-- 4. DROP VIEWS (before the tables they read)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 4: Dropping Views...
PROMPT ===================================================

BEGIN
    <<views_loop>>
    FOR rec IN (
        SELECT view_name
        FROM user_views
        WHERE view_name LIKE 'UC_AI%'
        ORDER BY view_name
    ) LOOP
        EXECUTE IMMEDIATE 'DROP VIEW ' || rec.view_name;
        sys.dbms_output.put_line('Dropped view: ' || rec.view_name);
    END LOOP views_loop;
END;
/

PROMPT Views dropped successfully.

-- ============================================================================
-- 5. DROP TABLES (Drop dependent tables first)
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 5: Dropping Tables...
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

-- ============================================================================
-- 6. DROP SEQUENCES
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 6: Dropping Sequences...
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
-- 7. VERIFY CLEANUP
-- ============================================================================

PROMPT
PROMPT ===================================================
PROMPT Step 7: Verification - Checking for Remaining Objects...
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
PROMPT - All UC AI views
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

