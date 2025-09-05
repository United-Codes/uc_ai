alter table uc_ai_tool_parameters drop constraint uc_ai_tool_parameters_array_props_ck;

alter table uc_ai_tool_parameters add
  constraint uc_ai_tool_parameters_array_props_ck check (
      (is_array = 1) 
      or 
      (is_array = 0 and array_min_items is null and array_max_items is null)
  );
