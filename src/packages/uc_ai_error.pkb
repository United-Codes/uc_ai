create or replace package body uc_ai_error as

  -- @dblinter ignore(g-9108)

  function get_default_message(
    p_error_code in number
  ) return varchar2
  is
  begin
    return case p_error_code
      -- Core / Provider
      when c_err_max_calls_exceeded     then c_msg_max_calls_exceeded
      when c_err_provider_response      then c_msg_provider_response
      when c_err_unhandled_format       then c_msg_unhandled_format
      when c_err_format_processing      then c_msg_format_processing
      when c_err_model_not_found        then c_msg_model_not_found
      when c_err_unknown_provider       then c_msg_unknown_provider
      when c_err_structured_unsupported then c_msg_structured_unsupported
      when c_err_reasoning_budget       then c_msg_reasoning_budget
      -- Agent
      when c_err_unknown_agent_type     then c_msg_unknown_agent_type
      when c_err_unknown_workflow_type  then c_msg_unknown_workflow_type
      when c_err_agent_retrieval        then c_msg_agent_retrieval
      when c_err_speaker_not_found      then c_msg_speaker_not_found
      when c_err_unknown_conv_mode      then c_msg_unknown_conv_mode
      -- Workflow
      when c_err_missing_output_key     then c_msg_missing_output_key
      when c_err_condition_eval         then c_msg_condition_eval
      when c_err_input_mapping_eval     then c_msg_input_mapping_eval
      when c_err_final_message_eval     then c_msg_final_message_eval
      when c_err_apex_session           then c_msg_apex_session
      -- Validation
      when c_err_not_found              then c_msg_not_found
      when c_err_invalid_status         then c_msg_invalid_status
      when c_err_missing_config         then c_msg_missing_config
      when c_err_invalid_config         then c_msg_invalid_config
      when c_err_has_references         then c_msg_has_references
      when c_err_missing_placeholder    then c_msg_missing_placeholder
      when c_err_unsupported_content    then c_msg_unsupported_content
      else 'Error ' || p_error_code
    end;
  end get_default_message;

  procedure raise_error(
    p_error_code in number
  , p_scope      in varchar2 default null
  , p0           in varchar2 default null
  , p1           in varchar2 default null
  , p2           in varchar2 default null
  , p3           in varchar2 default null
  , p4           in varchar2 default null
  , p5           in varchar2 default null
  , p6           in varchar2 default null
  , p7           in varchar2 default null
  , p8           in varchar2 default null
  , p9           in varchar2 default null
  , p_message    in varchar2 default null
  , p_extra      in clob     default null
  , p_log        in boolean  default true
  )
  is
    l_msg varchar2(2048 char);
  begin
    l_msg := apex_string.format(
      p_message    => coalesce(p_message, get_default_message(p_error_code))
    , p0           => p0
    , p1           => p1
    , p2           => p2
    , p3           => p3
    , p4           => p4
    , p5           => p5
    , p6           => p6
    , p7           => p7
    , p8           => p8
    , p9           => p9
    , p_max_length => 2048
    );

    if p_log then
      uc_ai_logger.log_error(
        p_text  => l_msg
      , p_scope => p_scope
      , p_extra => p_extra
      );
    end if;

    raise_application_error(p_error_code, l_msg);
  end raise_error;

  function parse_json_response(
    p_response in clob
  , p_provider in varchar2
  , p_scope    in varchar2
  ) return json_object_t
  is
    l_status_code number;
    l_preview     varchar2(500 char);
  begin
    return json_object_t.parse(p_response);
  exception
    when others then
      l_status_code := apex_web_service.g_status_code;
      l_preview := substr(p_response, 1, 500);

      raise_error(
        p_error_code => c_err_provider_response
      , p_scope      => p_scope
      , p0           => p_provider
      , p1           => 'Status Code from provider: ' || l_status_code || ', Provider response: ' || l_preview
      , p_extra      => p_response
      );
  end parse_json_response;

end uc_ai_error;
/
