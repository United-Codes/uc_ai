create or replace package body uc_ai_openai as 

  gc_scope_prefix constant varchar2(31) := lower($$plsql_unit) || '.';

 procedure generate_text (
    p_prompt        in clob
  , p_system_prompt in clob default null
  )
  as
    l_scope logger_logs.scope%type := gc_scope_prefix || 'todo_proc_name';

    l_input_obj    json_object_t := json_object_t();
    l_curr_message json_object_t;
    l_messages     json_array_t := json_array_t();
    l_tools        json_array_t;

    l_resp clob;
  begin
    l_input_obj.put('model', 'gpt-4o-mini');


    if p_system_prompt is not null then
      l_curr_message := json_object_t();
      l_curr_message.put('role', 'system');
      l_curr_message.put('content', p_system_prompt);
      l_messages.append(l_curr_message);
    end if;


    l_curr_message := json_object_t();
    l_curr_message.put('role', 'user');
    l_curr_message.put('content', p_prompt);
    l_messages.append(l_curr_message);
 
    l_input_obj.put('messages', l_messages);
    --l_input_obj.put('transfer_timeout', '60');

    l_tools := uc_ai.get_tools_array('openai');
    l_input_obj.put('tools', l_tools);

    logger.log('Request body', l_scope, l_input_obj.to_clob);

    apex_web_service.set_request_headers(
      p_name_01  => 'Content-Type',
      p_value_01 => 'application/json',
      p_name_02  => 'Authorization',
      p_value_02 => 'Bearer '||OPENAI_KEY
    );

    l_resp := apex_web_service.make_rest_request(
      p_url => 'https://api.openai.com/v1/chat/completions',
      p_http_method => 'POST',
      p_body => l_input_obj.to_clob
    );

    logger.log('Response', l_scope, l_resp);
  end generate_text;

end uc_ai_openai;
/
