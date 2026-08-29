-- Run the LLM-free utPLSQL suites: no provider is reached, so this is fast and free.
--
-- This list is curated, not discovered. `ut.run('uc_ai')` cannot be used instead:
-- 16 of the suites carry no --%suitepath annotation, so a suitepath run silently
-- reaches only about half of them, and a bare `ut.run` hits every live provider
-- suite. Keep this list in sync with the "LLM-free suites" section of
-- .claude/skills/prepare-release.md.

set serveroutput on size unlimited
set feedback off

-- The suites assert on numbers formatted as strings ('8.5'). A session with a
-- decimal comma (SQLcl picks up the OS locale) fails test_uc_ai_workflow_mapping
-- with "Actual: '8,5'". Pin the separators so the run is locale-independent.
alter session set nls_numeric_characters = '.,';

-- Without this SQLcl exits 0 even after an Oracle error, so a script that never
-- ran would look like a passing run.
whenever sqlerror exit failure
whenever oserror exit failure

-- The wire suites replace the HTTP transport, which only exists in a build
-- compiled with UC_AI_DEBUG:TRUE. Without this they would fail with -20502.
-- The flag stays on in this schema afterwards; it is a test schema.
@@enable_test_transport.sql

begin
  ut.run(ut_varchar2_list(
    'test_uc_ai_toon'
  , 'test_uc_ai_error'
  , 'test_uc_ai_utils'
  , 'test_uc_ai_message_api'
  , 'test_uc_ai_structured_output'
  , 'test_uc_ai_tools_api'
  , 'test_uc_ai_settings'
  , 'test_uc_ai_reset_globals'
  , 'test_uc_ai_passthrough'
  , 'test_uc_ai_reasoning_replay'
  , 'test_uc_ai_workflow_mapping'
  , 'test_uc_ai_agent_session_meta'
  , 'test_uc_ai_agent_validation'
  , 'test_uc_ai_hook'
  , 'test_uc_ai_wire'
  , 'test_uc_ai_wire_2'
  , 'test_uc_ai_wire_3'
  ));
end;
/

exit
