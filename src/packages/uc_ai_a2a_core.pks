create or replace package uc_ai_a2a_core
  authid definer
as

  /**
  * UC AI
  * PL/SQL SDK to integrate AI capabilities into Oracle databases.
  *
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) 2025-present United Codes
  * https://www.united-codes.com
  */

  /*
   * Internal engine of the A2A server (see uc_ai_a2a for the public API).
   *
   * Every operation takes and returns protocol objects as json_object_t, in the
   * A2A 1.0 JSON form (lowerCamelCase proto field names). The HTTP bindings
   * (JSON-RPC, REST) live in uc_ai_a2a; they only translate between HTTP and
   * these operations. A test can call the operations without HTTP.
   *
   * Ownership: every operation that works on a task takes the endpoint and the
   * client ID. A task of another client behaves like a missing task.
   *
   * Every failure of the protocol is an application error in the range
   * -20440 to -20458 (c_err_* below). get_error_info maps it to the code that a
   * binding puts on the wire.
   */

  -- ============================================================================
  -- Task states (proto enum TaskState, JSON name)
  -- ============================================================================

  c_state_submitted      constant varchar2(30 char) := 'TASK_STATE_SUBMITTED';
  c_state_working        constant varchar2(30 char) := 'TASK_STATE_WORKING';
  c_state_completed      constant varchar2(30 char) := 'TASK_STATE_COMPLETED';
  c_state_failed         constant varchar2(30 char) := 'TASK_STATE_FAILED';
  c_state_canceled       constant varchar2(30 char) := 'TASK_STATE_CANCELED';
  c_state_input_required constant varchar2(30 char) := 'TASK_STATE_INPUT_REQUIRED';
  c_state_rejected       constant varchar2(30 char) := 'TASK_STATE_REJECTED';
  c_state_auth_required  constant varchar2(30 char) := 'TASK_STATE_AUTH_REQUIRED';

  -- ============================================================================
  -- Error codes
  -- ============================================================================

  -- JSON-RPC level errors
  c_err_parse                constant number := -20440; -- JSON-RPC -32700
  c_err_invalid_request      constant number := -20441; -- JSON-RPC -32600
  c_err_method_not_found     constant number := -20442; -- JSON-RPC -32601
  c_err_invalid_params       constant number := -20443; -- JSON-RPC -32602
  -- A2A errors
  c_err_task_not_found       constant number := -20450; -- TASK_NOT_FOUND
  c_err_task_not_cancelable  constant number := -20451; -- TASK_NOT_CANCELABLE
  c_err_push_not_supported   constant number := -20452; -- PUSH_NOTIFICATION_NOT_SUPPORTED
  c_err_unsupported_op       constant number := -20453; -- UNSUPPORTED_OPERATION
  c_err_content_type         constant number := -20454; -- CONTENT_TYPE_NOT_SUPPORTED
  c_err_invalid_agent_resp   constant number := -20455; -- INVALID_AGENT_RESPONSE
  c_err_no_extended_card     constant number := -20456; -- EXTENDED_AGENT_CARD_NOT_CONFIGURED
  c_err_version_not_supported constant number := -20457; -- VERSION_NOT_SUPPORTED
  -- Not an A2A error: the caller is not authenticated (HTTP 401)
  c_err_unauthenticated      constant number := -20458;

  c_error_domain constant varchar2(30 char) := 'a2a-protocol.org';

  /*
   * What a binding puts on the wire for one error.
   *   jsonrpc_code  JSON-RPC error code
   *   http_status   HTTP status of the REST binding (and of JSON-RPC for 401)
   *   grpc_status   google.rpc.Code name, e.g. NOT_FOUND
   *   reason        UPPER_SNAKE_CASE A2A error type; null for plain protocol errors
   *   message       Text for the client. Never contains ORA- text or internals
   */
  type t_error_info is record (
    jsonrpc_code number,
    http_status  pls_integer,
    grpc_status  varchar2(30 char),
    reason       varchar2(60 char),
    message      varchar2(4000 char)
  );

  /*
   * Maps an error to its wire form. An error that is not one of the c_err_*
   * codes becomes the internal error: -32603, 500, "Internal error".
   */
  function get_error_info(
    p_sqlcode in number,
    p_sqlerrm in varchar2
  ) return t_error_info;

  /*
   * Raises the application error p_code with p_message.
   */
  procedure raise_error(
    p_code    in number,
    p_message in varchar2
  );

  -- ============================================================================
  -- Helpers
  -- ============================================================================

  /*
   * The endpoint with this code. Raises no_data_found when there is none.
   */
  function get_endpoint(
    p_code in varchar2
  ) return uc_ai_a2a_endpoints%rowtype;

  /*
   * Makes sure that the A2A-Version header names a version that this server
   * speaks (1.0, 1, or no header). Raises c_err_version_not_supported.
   */
  procedure check_version(
    p_version in varchar2
  );

  /*
   * True for a state a task never leaves.
   */
  function is_terminal(
    p_state in varchar2
  ) return boolean;

  /*
   * A new lowercase UUID (8-4-4-4-12).
   */
  function new_uuid return varchar2;

  /*
   * URL of the OAuth2 token endpoint that a card announces: p_card_extras
   * oauthTokenUrl, else <ords>/<schema>/oauth/token derived from the base URL
   * (the endpoint URL minus its last two path segments: endpoint and module path).
   */
  function get_token_url(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    p_base_url in varchar2
  ) return varchar2;

  -- ============================================================================
  -- Agent card
  -- ============================================================================

  /*
   * RSASSA-PKCS1-v1_5 with SHA-256 over p_data, through dbms_crypto.sign
   * (Oracle 21c or later). Raises c_err_signing when the key is not usable.
   *
   * @param p_private_key_pem  RSA private key in PEM form, without a password
   *                           (PKCS#8 or PKCS#1)
   * @param p_data             Data to sign, up to 32767 bytes
   */
  function sign_rs256(
    p_private_key_pem in clob,
    p_data            in raw
  ) return raw;

  /*
   * The agent card of an endpoint.
   *
   * @param p_endpoint  The endpoint
   * @param p_base_url  Public URL of the endpoint, without a trailing slash
   * @param p_extended  True for the extended card: the skill description also
   *                    holds the input and output schema of the agent
   */
  function build_agent_card(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    p_base_url in varchar2,
    p_extended in boolean default false
  ) return json_object_t;

  /*
   * GetExtendedAgentCard. Raises c_err_no_extended_card for auth mode none.
   */
  function get_extended_agent_card(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    p_base_url in varchar2
  ) return json_object_t;

  -- ============================================================================
  -- Operations. p_request / p_params is the request object of the proto message
  -- (SendMessageRequest, GetTaskRequest, ...). The REST binding builds the same
  -- object from path and query string.
  -- ============================================================================

  /*
   * SendMessage. Returns SendMessageResponse: {"task": Task}.
   * Runs the agent before it returns (a blocking call).
   */
  function send_message(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_request   in json_object_t
  ) return json_object_t;

  /*
   * SendStreamingMessage. Returns the StreamResponse events of the run, in
   * order: the task, the artifact update, the final status update.
   */
  function send_streaming_message(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_request   in json_object_t
  ) return json_array_t;

  /*
   * SubscribeToTask {id}. Returns the StreamResponse events.
   */
  function subscribe_to_task(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_array_t;

  /*
   * GetTask {id, historyLength}. Returns a Task.
   */
  function get_task(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t;

  /*
   * ListTasks {contextId, status, pageSize, pageToken, historyLength,
   * statusTimestampAfter, includeArtifacts}. Returns ListTasksResponse.
   */
  function list_tasks(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t;

  /*
   * CancelTask {id}. Returns a Task.
   */
  function cancel_task(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t;

  /*
   * CreateTaskPushNotificationConfig, GetTaskPushNotificationConfig,
   * ListTaskPushNotificationConfigs, DeleteTaskPushNotificationConfig.
   */
  function create_push_config(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t;

  function get_push_config(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t;

  function list_push_configs(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t;

  function delete_push_config(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t;

  /*
   * Runs a task that was accepted with returnImmediately (called by the
   * scheduler job through uc_ai_a2a.run_task).
   */
  procedure run_task(
    p_task_id in varchar2
  );

end uc_ai_a2a_core;
/
