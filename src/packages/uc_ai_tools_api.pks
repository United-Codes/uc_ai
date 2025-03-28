create or replace package uc_ai_tools_api as

  function get_tool_schema(
    p_tool_id in uc_ai_tools.id%type
  ) 
    return json_object_t 
  ;

  function get_tools_array (
    p_flavor in varchar2 default 'openai'
  ) return json_array_t;

  function execute_tool(
    p_tool_code in uc_ai_tools.code%type
  , p_arguments in json_object_t
  ) return clob;

end uc_ai_tools_api;
/
