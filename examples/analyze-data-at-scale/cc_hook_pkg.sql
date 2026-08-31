-- ============================================================================
-- UC AI tutorial — "Analyze Data at Scale" — Lesson 5
-- The execution hook of the cold-chain analyst
-- ============================================================================
-- A hook is a package UC AI calls around a run. before_execution and
-- after_execution are required. before_tool_call is optional, and UC AI finds it
-- by itself.
--
-- The important fact of this lesson is in before_tool_call: in code mode it
-- fires for EVERY callTool inside the program, not one time for the program. So
-- a program that reads 24 shipments fires it 25 times. Keep it cheap.
--
-- Set g_block_tool to a tool code to make the hook refuse that tool.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial package prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl.

create or replace package cc_hook_pkg
  authid definer
as
  -- @dblinter ignore(g-7230): both variables are public on purpose. The lesson reads
  -- g_calls from SQLcl to count the inner tool calls, and writes g_block_tool to make
  -- the hook refuse one tool. A getter pair would hide what the lesson is about.
  -- How many times before_tool_call ran since the last reset.
  g_calls number := 0;

  -- Set this to a tool code, and the hook refuses that tool.
  g_block_tool varchar2(255 char);

  procedure reset;

  procedure before_execution(
    p_agent_id    in number
  , p_agent_code  in varchar2
  , p_created_by  in varchar2
  , p_apex_app_id in number
  , p_session_id  in varchar2
  );

  procedure after_execution(
    p_exec_id       in number
  , p_status        in varchar2
  , p_input_tokens  in number
  , p_output_tokens in number
  );

  procedure before_tool_call(
    p_agent_id    in number
  , p_agent_code  in varchar2
  , p_tool_code   in varchar2
  , p_created_by  in varchar2
  , p_session_id  in varchar2
  , p_apex_app_id in number
  );
end cc_hook_pkg;
/

create or replace package body cc_hook_pkg
as
  procedure reset
  as
  begin
    g_calls      := 0;
    g_block_tool := null;
  end reset;

  procedure before_execution(
    p_agent_id    in number
  , p_agent_code  in varchar2
  , p_created_by  in varchar2
  , p_apex_app_id in number
  , p_session_id  in varchar2
  )
  as
    -- @dblinter ignore(g-7150): the signature is fixed by UC AI
  begin
    null;
  end before_execution;

  procedure after_execution(
    p_exec_id       in number
  , p_status        in varchar2
  , p_input_tokens  in number
  , p_output_tokens in number
  )
  as
    -- @dblinter ignore(g-7150): the signature is fixed by UC AI
  begin
    null;
  end after_execution;

  procedure before_tool_call(
    p_agent_id    in number
  , p_agent_code  in varchar2
  , p_tool_code   in varchar2
  , p_created_by  in varchar2
  , p_session_id  in varchar2
  , p_apex_app_id in number
  )
  as
    -- @dblinter ignore(g-7150): the signature is fixed by UC AI
  begin
    -- This runs once for the uc_ai__run_code call itself, and then once more for
    -- each callTool the program makes. Count them and see.
    g_calls := g_calls + 1;

    if p_tool_code = g_block_tool then
      -- A raise here is a VETO. It stops the whole request, and the program
      -- cannot catch its way past it.
      raise_application_error(-20999, 'Policy: ' || p_tool_code || ' is not allowed now.');
    end if;
  end before_tool_call;
end cc_hook_pkg;
/
