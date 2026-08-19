create or replace package test_uc_ai_message_api as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(Message API content and message builders)
  --%suitepath(uc_ai)

  -- LLM-free unit tests for uc_ai_message_api JSON builders

  --%test(create_text_content builds a text content object)
  procedure text_content_shape;

  --%test(create_text_content includes providerOptions only when passed)
  procedure text_content_provider_options;

  --%test(create_text_content preserves a CLOB larger than 32k)
  procedure text_content_clob_32k;

  --%test(create_file_content CLOB overload builds a file content object)
  procedure file_content_clob_overload;

  --%test(create_file_content omits filename when null)
  procedure file_content_no_filename;

  --%test(create_file_content BLOB overload base64-encodes round-trippable data)
  procedure file_content_blob_overload;

  --%test(create_reasoning_content builds a reasoning content object)
  procedure reasoning_content_shape;

  --%test(create_reasoning_content omits text key when text is null (no literal "null" string))
  procedure reasoning_content_null_text;

  --%test(create_tool_call_content builds a tool call content object)
  procedure tool_call_content_shape;

  --%test(create_tool_result_content builds a tool result content object)
  procedure tool_result_content_shape;

  --%test(create_system_message builds a scalar-content system message)
  procedure system_message_shape;

  --%test(user, assistant and tool messages carry the content array)
  procedure array_message_shapes;

  --%test(create_simple_user_message wraps text in a one-element content array)
  procedure simple_user_message;

  --%test(create_simple_assistant_message wraps text in a one-element content array)
  procedure simple_assistant_message;

  --%test(create_user_message with files appends text and file content blocks)
  procedure user_message_with_files;

  --%test(create_user_message with empty files matches simple_user_message)
  procedure user_message_empty_files;

  --%test(create_user_message with null text and files omits the text block)
  procedure user_message_files_no_text;

end test_uc_ai_message_api;
/
