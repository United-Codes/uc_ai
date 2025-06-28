create or replace package body uc_ai as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  procedure generate_text (
    p_prompt        in clob
  , p_system_prompt in clob default null
  )
  as
  begin
    -- TODO: Implement provider selection logic if needed
    uc_ai_openai.generate_text(
      p_prompt        => p_prompt
    , p_system_prompt => p_system_prompt
    );

  end generate_text;

end uc_ai;
/
