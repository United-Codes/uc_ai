-- @dblinter ignore(g-5010): allow dbms_output usage

declare
  l_logger_exists number := 0;
  l_sql varchar2(1000 char);
begin
  -- Check if logger package exists (either local or via public synonym)
  select count(*) -- @dblinter ignore(g-8110): fine here
    into l_logger_exists
    from all_objects
   where object_name = 'LOGGER'
     and object_type = 'PACKAGE'
     and (owner = user or owner = 'PUBLIC');
  
  if l_logger_exists > 0 then
    sys.dbms_output.put_line('Logger package detected. Setting USE_LOGGER flag to TRUE.');
    l_sql := q'!alter package uc_ai_logger compile plsql_ccflags = 'USE_LOGGER:TRUE'!';
    execute immediate l_sql;
    sys.dbms_output.put_line('Successfully compiled uc_ai_logger package with USE_LOGGER flag.');
  end if;
end;
/
