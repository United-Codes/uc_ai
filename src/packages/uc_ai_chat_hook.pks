create or replace package uc_ai_chat_hook
  authid definer
as

  -- ============================================================================
  -- UC AI Chat - optional progress hook
  -- ----------------------------------------------------------------------------
  -- Registered per scheduler-job session by uc_ai_chat.execute_agent_job via
  -- uc_ai_agents_api.set_execution_hook, so the core agent framework dispatches
  -- its execution hooks here. Its own job is to write provisional "tool running"
  -- placeholder rows into uc_ai_chat_messages (in before_tool_call) so the chat
  -- UI can show which tool is executing while a turn is still running.
  --
  -- Every hook procedure ALSO delegates to a customer's conventional UC_AI_HOOK
  -- package (in the same schema) if one is installed and implements it. That way
  -- activating this override never silently disables an existing customer hook
  -- such as a budget hard-cap. Veto hooks (before_execution / before_tool_call)
  -- propagate the customer's exceptions; best-effort hooks (after_execution /
  -- augment_system_prompt) swallow them, matching the core's own semantics.
  --
  -- Installing this package is what activates progressive tool progress; the
  -- feature is a no-op (and never dispatched to) when it is absent, so it is
  -- entirely optional.
  -- ============================================================================

  -- Sets the current turn context (called by execute_agent_job before the run).
  procedure set_chat_context(
    p_user_msg_id in number,
    p_session_id  in varchar2,
    p_created_by  in varchar2
  );

  -- ---- Core execution hook surface (signatures per uc_ai_agents_api spec) ----

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

end uc_ai_chat_hook;
/
