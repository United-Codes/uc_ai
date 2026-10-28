create or replace package uc_ai_chat 
  authid definer
as

  -- ============================================================================
  -- UC AI Chat - APEX Region Plugin
  -- Provides an AI chat interface using UC AI agent framework.
  --
  -- Each turn is one 'user' row in uc_ai_chat_messages carrying a turn_status
  -- lifecycle: pending -> processing -> done | error | cancelled. The background
  -- job (execute_agent_job) drives the status; AI_FETCH_MESSAGES reports it (and
  -- sweeps orphaned jobs); AI_CANCEL cooperatively stops a turn. Real error text
  -- is stored in error_detail and returned only when the show_errors debug flag
  -- is on.
  --
  -- Guardrails (optional UC AI Pro layer) are surfaced but never enforced here:
  -- AI_SEND_MESSAGE and AI_FETCH_MESSAGES report a coarse {state, kind} in a
  -- 'guardrail' member when the caller is close to or past a limit, and a turn
  -- refused by a limit carries turn.guardrail. Both are ungated - the kind names
  -- no limit, figure or percentage - while the underlying sqlerrm stays behind
  -- show_errors. Degrades to a silent no-op without the pro packages.
  --
  -- The conversation title and the end user's feedback both live on the core
  -- session header (uc_ai_agent_sessions), not in this plug-in's tables: neither
  -- is specific to APEX chat, and the core row is already 1:1 with a conversation.
  -- Both writes pass p_created_by => null and rely on assert_session_owner, because
  -- that header's created_by is the background job's DB user, not APP_USER.
  --
  -- Widgets (optional, region attribute "widgets"): the model may put a small
  -- widget (stat_card, status, key_value, table, chart) into its answer as a
  -- fenced ucai-widget JSON block. AI_SEND_MESSAGE normalises the enabled types
  -- from the region attribute only (never from the client) into
  -- uc_ai_chat_messages.widgets on the user row. On the first turn
  -- execute_agent_job passes the widget protocol as p_prompt_addendum. After the
  -- run it renders the answer ONCE against this turn's tool calls
  -- (uc_ai_chat_widgets.render) and stores the validated parts on the assistant
  -- row (uc_ai_chat_messages.parts), only when the answer holds a widget or a
  -- rejected one; a failure there never fails the turn. AI_FETCH_MESSAGES emits
  -- that snapshot as a 'parts' array next to the unchanged 'content'; the reason
  -- a widget was rejected follows the show_errors debug flag. Needs the UC AI
  -- release that adds uc_ai_agent_messages.tool_call_id and p_prompt_addendum.
  --
  -- AJAX methods (dispatched on g_x01): AI_NEW_SESSION, AI_SET_TITLE,
  -- AI_SET_FEEDBACK, AI_SEND_MESSAGE, AI_FETCH_MESSAGES, AI_EXEC_DETAILS,
  -- AI_CANCEL.
  -- ============================================================================

  procedure render_region(
    p_plugin in            apex_plugin.t_plugin,
    p_region in            apex_plugin.t_region,
    p_param  in            apex_plugin.t_region_render_param,
    p_result in out nocopy apex_plugin.t_region_render_result -- @dbLinter ignore(G-9110) For API compatibility
  );

  procedure ajax_region(
    p_plugin in            apex_plugin.t_plugin,
    p_region in            apex_plugin.t_region,
    p_param  in            apex_plugin.t_region_ajax_param,
    p_result in out nocopy apex_plugin.t_region_ajax_result -- @dbLinter ignore(G-9110) For API compatibility
  );

  -- Background job entry point for async agent execution
  procedure execute_agent_job(
    p_user_msg_id in number
  );

end uc_ai_chat;
/
