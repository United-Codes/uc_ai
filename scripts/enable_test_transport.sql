-- Compile uc_ai_http with the debug flag, so uc_ai_http.set_transport works and
-- test_uc_ai_wire* can intercept provider requests.
--
-- NEVER run this in production: the flag compiles a dynamic call into
-- uc_ai_http.post that a registered package can use to answer provider requests.
--
-- Turn it back off with:
--   alter package uc_ai_http compile body plsql_ccflags = 'UC_AI_DEBUG:FALSE' reuse settings;
-- or by reinstalling the package from src/packages/uc_ai_http.pkb.

set serveroutput on
set feedback off

alter package uc_ai_http compile body plsql_ccflags = 'UC_AI_DEBUG:TRUE' reuse settings;

declare
  l_enabled varchar2(4000 char);
begin
  select nvl(max(plsql_ccflags), 'none')
    into l_enabled
    from user_plsql_object_settings
   where name = 'UC_AI_HTTP'
     and type = 'PACKAGE BODY';

  sys.dbms_output.put_line('uc_ai_http body compiled with: ' || l_enabled);
end;
/
