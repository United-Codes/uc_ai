create or replace package uc_ai as

  function get_tool_schema(
    p_tool_id in uc_ai_tools.id%type
  ) 
    return json_object_t 
  ;

  procedure generate_text (
    p_prompt in varchar2
  );

end uc_ai;
/
