-- ============================================================================
-- Removes what the install scripts of this application created: the backend of
-- the UC AI Chat plug-in.
--
-- It does NOT remove UC AI, and it does NOT remove the demo schema of a course.
-- Every course has its own 00_teardown.sql for that.
--
-- The message table goes with it, so every conversation of every chat region in
-- this schema is deleted.
-- ============================================================================
begin
  for r in (
    select 'package ' || object_name as obj
      from user_objects
     where object_type = 'PACKAGE'
       and object_name in ('UC_AI_CHAT', 'UC_AI_CHAT_HOOK')
    union all
    select 'table ' || table_name || ' cascade constraints purge'
      from user_tables
     where table_name = 'UC_AI_CHAT_MESSAGES'
    union all
    select 'sequence ' || sequence_name
      from user_sequences
     where sequence_name = 'UC_AI_CHAT_MESSAGES_SEQ'
  )
  loop
    execute immediate 'drop ' || r.obj;
  end loop;
end;
/
