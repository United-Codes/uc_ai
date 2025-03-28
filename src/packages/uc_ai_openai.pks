create or replace package uc_ai_openai as


  procedure generate_text (
    p_prompt        in clob
  , p_system_prompt in clob default null
  );

end uc_ai_openai;
/
