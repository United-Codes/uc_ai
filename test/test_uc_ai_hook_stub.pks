create or replace package test_uc_ai_hook_stub as
  -- @dblinter ignore(g-5010): allow logger in test packages
  -- @dblinter ignore(g-7230): allow use of global variables in test stub

  /*
   * Fake execution-hook implementation used by test_uc_ai_hook.
   * Implements the uc_ai_agents_api execution-hook contract
   * (before_execution / after_execution) and records what it was called with,
   * so the test suite can assert dispatch, vetoing and best-effort behaviour
   * without needing a real UC_AI_HOOK package or an LLM call.
   */

  -- distinctive error codes so the suite can tell veto/after errors apart
  c_before_veto_code constant pls_integer := -20099;
  c_after_fail_code   constant pls_integer := -20098;
  c_tool_veto_code    constant pls_integer := -20097;
  c_prompt_fail_code  constant pls_integer := -20096;

  -- recorded call state
  g_before_count      pls_integer;
  g_after_count       pls_integer;

  -- last before_execution args
  g_last_agent_id     number;
  g_last_agent_code   varchar2(255 char);
  g_last_created_by   varchar2(255 char);
  g_last_apex_app_id  number;
  g_last_session_id   varchar2(255 char);

  -- last after_execution args
  g_last_exec_id      number;
  g_last_status       varchar2(50 char);
  g_last_in_tokens    number;
  g_last_out_tokens   number;

  -- last before_tool_call args
  g_tool_count        pls_integer;
  g_last_tool_code    varchar2(255 char);
  g_last_tool_agent   varchar2(255 char);
  g_last_tool_user    varchar2(255 char);

  -- last augment_system_prompt args
  g_prompt_count      pls_integer;
  g_last_prompt_in    clob;                       -- prompt as received by the stub

  -- behaviour switches
  g_before_raise      boolean;
  g_after_raise       boolean;
  g_tool_raise        boolean;
  g_prompt_raise      boolean;                    -- raise AFTER mutating (tests copy protection)
  g_prompt_append     varchar2(4000 char);        -- appended to the prompt when set

  -- Reset all recorded state and behaviour switches
  procedure reset;

  -- Hook contract
  procedure before_execution(
    p_agent_id    in number,
    p_agent_code  in varchar2,
    p_created_by  in varchar2,
    p_apex_app_id in number,
    p_session_id  in varchar2
  );

  procedure after_execution(
    p_exec_id       in number,
    p_status        in varchar2,
    p_input_tokens  in number,
    p_output_tokens in number
  );

  procedure before_tool_call(
    p_agent_id    in number,
    p_agent_code  in varchar2,
    p_tool_code   in varchar2,
    p_created_by  in varchar2,
    p_session_id  in varchar2,
    p_apex_app_id in number
  );

  procedure augment_system_prompt(
    pio_system_prompt in out nocopy clob
  );

end test_uc_ai_hook_stub;
/
