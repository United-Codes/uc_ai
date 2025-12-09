create or replace package uc_ai_openrouter as
  -- @dblinter ignore(g-7230): allow use of global variables

  /**
  * UC AI
  * Package to integrate AI capabilities into Oracle databases.
  * 
  * Copyright (c) 2025 United Codes
  * https://www.united-codes.com
  */


  -- get models from https://openrouter.ai/models

  -- How many reasoning tokens to generate before creating a response
  -- More info at https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request#request.body.reasoning
  g_reasoning_effort varchar2(32 char) := 'low'; -- 'minimal', 'low', 'medium', 'high'

  -- type: HTTP-Header, credential-name: Authorization, value: Bearer <token>
  g_apex_web_credential varchar2(255 char);

end uc_ai_openrouter;
/
