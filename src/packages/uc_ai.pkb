create or replace package body uc_ai as

  c_scope_prefix           constant varchar2(31 char) := lower($$plsql_unit) || '.';
  c_default_max_tool_calls constant pls_integer := 10;

  function generate_text (
    p_user_prompt    in clob
  , p_system_prompt  in clob default null
  , p_provider       in provider_type
  , p_model          in model_type
  , p_max_tool_calls in pls_integer default null
  ) return json_object_t
  as
    e_unknown_provider exception;

    l_result json_object_t;
  begin
    case p_provider
      when c_provider_openai then
        l_result := uc_ai_openai.generate_text(
          p_user_prompt    => p_user_prompt
        , p_system_prompt  => p_system_prompt
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, c_default_max_tool_calls)
        );
      when c_provider_anthropic then
        l_result := uc_ai_anthropic.generate_text(
          p_user_prompt    => p_user_prompt
        , p_system_prompt  => p_system_prompt
        , p_model          => p_model
        , p_max_tool_calls => coalesce(p_max_tool_calls, c_default_max_tool_calls)
        );
      else
        raise e_unknown_provider;
    end case;
   
  
    return l_result;
  exception
    when e_unknown_provider then
      raise_application_error(-20001, 'Unknown AI provider: ' || p_provider);
    when others then
      raise;
  end generate_text;

end uc_ai;
/
