create or replace package body uc_ai as

  gc_scope_prefix           constant varchar2(31 char) := lower($$plsql_unit) || '.';
  gc_default_max_tool_calls constant pls_integer := 10;

  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_max_tool_calls in pls_integer default null
  ) return json_object_t
  as
    l_result json_object_t;
  begin
    -- TODO: Implement provider selection logic if needed
    l_result := uc_ai_openai.generate_text(
      p_user_prompt    => p_user_prompt
    , p_system_prompt  => p_system_prompt
    , p_max_tool_calls => coalesce(p_max_tool_calls, gc_default_max_tool_calls)
    );
  
    return l_result;
  end generate_text;

end uc_ai;
/
