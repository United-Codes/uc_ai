create or replace package uc_ai as

  function get_tool_schema(
    p_tool_id in uc_ai_tools.id%type
  ) 
    return json_object_t 
  ;

  function get_tools_array (
    p_flavor in varchar2 default 'openai'
  ) return json_array_t;

  procedure generate_text (
    p_prompt        in clob
  , p_system_prompt in clob default null
  );

end uc_ai;
/
