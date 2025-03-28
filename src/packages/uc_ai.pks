create or replace package uc_ai as

  FUNCTION get_tool_schema(p_tool_id IN NUMBER) 
    RETURN JSON_OBJECT_T 
  ;

end uc_ai;
/
