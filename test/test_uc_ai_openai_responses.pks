create or replace package test_uc_ai_openai_responses as

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  /**
   * Test package for uc_ai_openai using Responses API
   * 
   * Tests OpenAI integration via the Responses API (now the default)
   */

  --%suite(UC AI OpenAI Responses API Tests)
  --%suitepath(uc_ai)

  --%beforeall
  procedure setup_tests;

  --%test(Simple text generation with string input)
  procedure test_simple_string_input;

  --%test(Multi-turn conversation with previous_response_id)
  procedure test_multi_turn_conversation;

  --%test(Function calling with Responses API)
  procedure test_function_calling;

  --%test(Function calling - clock in user)
  procedure test_tool_clock_in_user;

  --%test(Structured output with text.format)
  procedure test_structured_output;

  --%test(PDF file input)
  procedure test_pdf_file_input;

  --%test(Image file input)
  procedure test_image_file_input;

  --%test(System instructions parameter)
  procedure test_instructions;

  --%test(Reasoning configuration)
  procedure test_reasoning_config;

  --%test(Encrypted reasoning for ZDR compliance)
  procedure test_encrypted_reasoning;

  --%test(Function calling with reasoning model, store=false, no encrypted reasoning)
  procedure test_function_calling_reasoning;

end test_uc_ai_openai_responses;
/
