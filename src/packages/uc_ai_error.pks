create or replace package uc_ai_error 
  authid definer
as

  -- @dblinter ignore(g-9108)

  /**
  * UC AI - Centralized Error Handling
  * Defines error codes, message templates, and a raise_error procedure
  * that logs and raises with descriptive messages in one call.
  *
  * Each error code has a default message template. Placeholders use
  * apex_string.format syntax: %0, %1, %2, ... %9
  *
  * Example:
  *   uc_ai_error.raise_error(
  *     p_error_code => uc_ai_error.c_err_unknown_provider
  *   , p0           => 'my_provider'
  *   );
  *   -- raises: ORA-20306: Unknown AI provider: my_provider
  *
  * Override the default message when needed:
  *   uc_ai_error.raise_error(
  *     p_error_code => uc_ai_error.c_err_provider_response
  *   , p_message    => 'Response is not valid JSON'
  *   , p_extra      => l_resp
  *   );
  *
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  -- =============================================
  -- Error code constants
  -- Range -20301 to -20309: Core / provider errors
  -- Range -20400 to -20409: Agent errors
  -- Range -20450 to -20459: Workflow errors
  -- Range -20500 to -20509: Validation errors
  -- =============================================

  -- Core / Provider errors (preserving existing codes from uc_ai.pks)
  c_err_max_calls_exceeded     constant number := -20301;
  c_err_provider_response      constant number := -20302;
  c_err_unhandled_format       constant number := -20303;
  c_err_format_processing      constant number := -20304;
  c_err_model_not_found        constant number := -20305;
  c_err_unknown_provider       constant number := -20306;
  c_err_structured_unsupported constant number := -20307;
  c_err_reasoning_budget       constant number := -20308;

  -- Agent errors
  c_err_unknown_agent_type     constant number := -20400;
  c_err_unknown_workflow_type  constant number := -20401;
  c_err_agent_retrieval        constant number := -20402;
  c_err_speaker_not_found      constant number := -20403;
  c_err_unknown_conv_mode      constant number := -20404;

  -- Workflow errors
  c_err_missing_output_key     constant number := -20450;
  c_err_condition_eval         constant number := -20451;
  c_err_input_mapping_eval     constant number := -20452;
  c_err_final_message_eval     constant number := -20453;
  c_err_apex_session           constant number := -20454;

  -- Validation errors
  c_err_not_found              constant number := -20500;
  c_err_invalid_status         constant number := -20501;
  c_err_missing_config         constant number := -20502;
  c_err_invalid_config         constant number := -20503;
  c_err_has_references         constant number := -20505;
  c_err_missing_placeholder    constant number := -20506;
  c_err_unsupported_content    constant number := -20508;

  -- =============================================
  -- Default message templates (apex_string.format syntax)
  -- These are used automatically by raise_error when p_message is null.
  -- They are public so callers can reference them for documentation.
  -- =============================================

  -- Core / Provider messages
  c_msg_max_calls_exceeded     constant varchar2(200 char) := 'Maximum tool calls exceeded (limit: %0)';
  c_msg_provider_response      constant varchar2(200 char) := 'Error response from provider %0: %1';
  c_msg_unhandled_format       constant varchar2(200 char) := 'Unsupported %0: %1';
  c_msg_format_processing      constant varchar2(200 char) := 'Error processing format: %0';
  c_msg_model_not_found        constant varchar2(200 char) := 'Model not found: %0';
  c_msg_unknown_provider       constant varchar2(200 char) := 'Unknown AI provider: %0';
  c_msg_structured_unsupported constant varchar2(200 char) := 'Provider %0 does not support structured output';
  c_msg_reasoning_budget       constant varchar2(200 char) := 'Reasoning budget tokens (%0) exceed max tokens (%1). Set a higher value.';

  -- Agent messages
  c_msg_unknown_agent_type     constant varchar2(200 char) := 'Unknown agent type: %0';
  c_msg_unknown_workflow_type  constant varchar2(200 char) := 'Unknown workflow type: %0';
  c_msg_agent_retrieval        constant varchar2(200 char) := 'Error retrieving agent: %0';
  c_msg_speaker_not_found      constant varchar2(200 char) := 'Next speaker "%0" not found among participants';
  c_msg_unknown_conv_mode      constant varchar2(200 char) := 'Unknown conversation mode: %0';

  -- Workflow messages
  c_msg_missing_output_key     constant varchar2(200 char) := 'Step definition missing output_key';
  c_msg_condition_eval         constant varchar2(200 char) := 'Error evaluating condition: %0 - %1';
  c_msg_input_mapping_eval     constant varchar2(200 char) := 'Error evaluating input mapping key %0: %1';
  c_msg_final_message_eval     constant varchar2(200 char) := 'Error evaluating final_message: %0 - %1';
  c_msg_apex_session           constant varchar2(500 char) := 'Cannot create APEX session. Schema needs an APEX Workspace with at least one application.';

  -- Validation messages
  c_msg_not_found              constant varchar2(200 char) := '%0 not found: %1';
  c_msg_invalid_status         constant varchar2(200 char) := 'Invalid status value: %0. Allowed: %1';
  c_msg_missing_config         constant varchar2(200 char) := '%0 requires %1';
  c_msg_invalid_config         constant varchar2(200 char) := 'Invalid %0: %1';
  c_msg_has_references         constant varchar2(200 char) := 'Cannot delete "%0": referenced by %1 record(s)';
  c_msg_missing_placeholder    constant varchar2(200 char) := 'Missing parameter for placeholder: %0';
  c_msg_unsupported_content    constant varchar2(200 char) := 'Unsupported content type: %0';

  /**
   * Log an error and raise raise_application_error in one call.
   *
   * The default message template for each error code is used automatically.
   * Pass p_message only to override the default.
   *
   * @param p_error_code  One of the c_err_* constants
   * @param p_scope       Logger scope (e.g., 'uc_ai_agents_api.create_agent')
   * @param p0            Substitution value for %0
   * @param p1            Substitution value for %1
   * @param p2            Substitution value for %2
   * @param p3            Substitution value for %3
   * @param p4            Substitution value for %4
   * @param p5            Substitution value for %5
   * @param p6            Substitution value for %6
   * @param p7            Substitution value for %7
   * @param p8            Substitution value for %8
   * @param p9            Substitution value for %9
   * @param p_message     Override message template. If null, the default for p_error_code is used.
   * @param p_extra       Extra detail passed to uc_ai_logger.log_error (e.g., full JSON response or backtrace)
   * @param p_log         Whether to log before raising (default true). Set to false when re-raising in an exception handler where logging already happened.
   */
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
  );

  /**
   * Parse a provider HTTP response as JSON, raising a descriptive error on failure.
   *
   * Replaces scattered begin/exception blocks across providers.
   * On failure, the raised error includes the provider name,
   * the HTTP status code, and a truncated preview of the response body.
   *
   * @param p_response   Raw HTTP response body (may be HTML, empty, etc.)
   * @param p_provider   Provider name for the error message (e.g. 'Ollama', 'OCI')
   * @param p_scope      Logger scope
   * @return Parsed JSON object
   */
  function parse_json_response(
    p_response in clob
  , p_provider in varchar2
  , p_scope    in varchar2
  ) return json_object_t;

end uc_ai_error;
/
