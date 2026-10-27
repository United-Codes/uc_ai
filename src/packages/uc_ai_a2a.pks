create or replace package uc_ai_a2a
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
   * A2A (Agent2Agent protocol 1.0) server for UC AI agents.
   *
   * Publishes an agent of uc_ai_agents as an A2A agent, so that other systems can
   * find it through its agent card and send it messages over HTTP. Both standard
   * HTTP bindings are served: JSON-RPC and HTTP+JSON (REST).
   *
   * Typical setup:
   *
   *   begin
   *     uc_ai_a2a.install_ords_module;                     -- once per schema
   *     uc_ai_a2a.expose_agent(
   *       p_code       => 'support'
   *     , p_agent_code => 'support_bot'
   *     );
   *     dbms_output.put_line(uc_ai_a2a.create_api_key('support', 'crm_system'));
   *   end;
   *
   * The agent card is then at <ords>/<schema>/a2a/support/.well-known/agent-card.json.
   *
   * The ORDS handlers call handle_request. Any other HTTP front end can call
   * process_request, which neither reads the CGI environment nor writes output.
   */

  -- Authentication modes of an endpoint
  c_auth_api_key constant varchar2(20 char) := 'api_key';
  c_auth_oauth2  constant varchar2(20 char) := 'oauth2';
  c_auth_none    constant varchar2(20 char) := 'none';

  -- The protocol version this server speaks
  c_protocol_version constant varchar2(10 char) := '1.0';

  -- The request header that carries an API key
  c_api_key_header constant varchar2(30 char) := 'X-API-Key';

  -- Routes of handle_request / process_request
  c_route_card    constant varchar2(20 char) := 'card';
  c_route_jsonrpc constant varchar2(20 char) := 'jsonrpc';
  c_route_rest    constant varchar2(20 char) := 'rest';

  -- Error codes (range -20430 to -20439)
  c_err_endpoint_not_found constant number := -20430;
  c_err_invalid_endpoint   constant number := -20431;
  c_err_ords_missing       constant number := -20432;
  c_err_crypto_missing     constant number := -20433;
  c_err_api_key            constant number := -20434;
  c_err_signing            constant number := -20435;

  /*
   * The answer to one HTTP request.
   *   status        HTTP status code
   *   content_type  value of the Content-Type header
   *   body          response body (JSON, or Server-Sent Events for a stream)
   */
  type t_http_response is record (
    status       pls_integer,
    content_type varchar2(100 char),
    body         clob
  );

  -- ============================================================================
  -- Endpoints
  -- ============================================================================

  /*
   * Publishes an agent as an A2A endpoint. Creates the endpoint, or replaces the
   * configuration of an endpoint with the same code.
   *
   * @param p_code              URL slug of the endpoint: lowercase letters, digits, '_' and '-'
   * @param p_agent_code        Code of the agent to run
   * @param p_agent_version     Version of the agent; null runs the active version
   * @param p_name              Name on the agent card; null uses the agent code
   * @param p_description       Description on the agent card; null uses the agent description
   * @param p_text_input_param  Input parameter that the text of a message fills on the first
   *                            turn. Null: when the input schema of the agent has exactly one
   *                            required string property, that property; otherwise text input
   *                            is refused and clients must send a data part
   * @param p_auth_mode         c_auth_api_key (default), c_auth_oauth2 or c_auth_none
   * @param p_accept_files      Accept file parts (raw bytes) and pass them to the agent
   * @param p_allow_async       Allow returnImmediately and push notifications
   * @param p_card_version      Version on the agent card
   * @param p_base_url          Public URL of the endpoint, e.g. https://api.example.com/ords/app/a2a/support.
   *                            Null derives it from each request (fine without a reverse proxy)
   * @param p_card_extras       JSON object with optional card content: provider {organization, url},
   *                            documentationUrl, iconUrl, tags [..], examples [..], oauthTokenUrl
   * @return                    ID of the endpoint
   */
  function expose_agent(
    p_code             in varchar2,
    p_agent_code       in varchar2,
    p_agent_version    in number   default null,
    p_name             in varchar2 default null,
    p_description      in varchar2 default null,
    p_text_input_param in varchar2 default null,
    p_auth_mode        in varchar2 default c_auth_api_key,
    p_accept_files     in boolean  default true,
    p_allow_async      in boolean  default true,
    p_card_version     in varchar2 default '1.0.0',
    p_base_url         in varchar2 default null,
    p_card_extras      in clob     default null
  ) return number;

  /*
   * Same as the function, without the ID.
   */
  procedure expose_agent(
    p_code             in varchar2,
    p_agent_code       in varchar2,
    p_agent_version    in number   default null,
    p_name             in varchar2 default null,
    p_description      in varchar2 default null,
    p_text_input_param in varchar2 default null,
    p_auth_mode        in varchar2 default c_auth_api_key,
    p_accept_files     in boolean  default true,
    p_allow_async      in boolean  default true,
    p_card_version     in varchar2 default '1.0.0',
    p_base_url         in varchar2 default null,
    p_card_extras      in clob     default null
  );

  /*
   * Enables or disables an endpoint. A disabled endpoint answers 404 on every route.
   */
  procedure set_enabled(
    p_code    in varchar2,
    p_enabled in boolean
  );

  /*
   * Deletes an endpoint with its API keys, tasks and push notification
   * configurations, and its ORDS privilege. The agent and its executions stay.
   */
  procedure remove_endpoint(
    p_code in varchar2
  );

  -- ============================================================================
  -- API keys (auth mode c_auth_api_key)
  -- ============================================================================

  /*
   * Creates an API key for a client of an endpoint. Only a hash of the key is
   * stored, so this is the only time the key is visible. Needs execute on
   * dbms_crypto (raises c_err_crypto_missing without it).
   *
   * @param p_endpoint_code  Code of the endpoint
   * @param p_client_name    Name of the client system; unique per endpoint. The tasks of
   *                         a client are visible to that client only
   * @param p_expires_at     Optional end of validity
   * @return                 The API key
   */
  function create_api_key(
    p_endpoint_code in varchar2,
    p_client_name   in varchar2,
    p_expires_at    in timestamp default null
  ) return varchar2;

  /*
   * Revokes the API key of a client. Requests with that key fail with 401 at once.
   */
  procedure revoke_api_key(
    p_endpoint_code in varchar2,
    p_client_name   in varchar2
  );

  -- ============================================================================
  -- ORDS
  -- ============================================================================

  /*
   * Creates (or recreates) the ORDS module that serves every endpoint, and the
   * OAuth2 privileges of endpoints with auth mode c_auth_oauth2. The schema must
   * be REST-enabled (ords.enable_schema). Raises c_err_ords_missing without ORDS.
   *
   * @param p_base_path    Base path of the module below the schema URL
   * @param p_module_name  Name of the ORDS module
   */
  procedure install_ords_module(
    p_base_path   in varchar2 default 'a2a/',
    p_module_name in varchar2 default 'uc_ai_a2a'
  );

  /*
   * Deletes the ORDS module and the OAuth2 privileges and roles of the endpoints.
   */
  procedure uninstall_ords_module(
    p_module_name in varchar2 default 'uc_ai_a2a'
  );

  /*
   * Creates an ORDS OAuth2 client (client credentials flow) that may call an
   * endpoint with auth mode c_auth_oauth2. The client gets a token from
   * <ords>/<schema>/oauth/token and sends it as a bearer token.
   *
   * @param p_endpoint_code   Code of the endpoint
   * @param p_client_name     Name of the OAuth client (unique in the schema)
   * @param p_support_email   Contact address that ORDS stores with the client
   * @param po_client_id      Client ID; it is also the identity the tasks belong to
   * @param po_client_secret  Client secret; only visible now
   */
  procedure create_oauth_client(
    p_endpoint_code  in  varchar2,
    p_client_name    in  varchar2,
    p_support_email  in  varchar2,
    po_client_id     out varchar2,
    po_client_secret out varchar2
  );

  -- ============================================================================
  -- Card signing
  -- ============================================================================

  /*
   * Signs the agent card of an endpoint with a private key (RS256, JWS per A2A
   * section 8.4). The public card and the extended card both carry the signature.
   * The signature covers the RFC 8785 (JCS) canonical form of the card without
   * its signatures, as the A2A SDK builds it. Needs Oracle 21c or later and
   * execute on dbms_crypto. Pass a null key to stop signing.
   *
   * The key is stored as given, in uc_ai_a2a_endpoints.signing_key: restrict
   * access to that table. The key is tried once here, so an unusable key raises
   * c_err_signing now. The signed input must stay below 32 KB (a card of about
   * 24 KB); a larger card is served without a signature and the error is logged.
   *
   * @param p_endpoint_code    Code of the endpoint
   * @param p_kid              Key ID put into the protected header
   * @param p_private_key_pem  RSA private key, PEM, no password (PKCS#8 "BEGIN PRIVATE KEY" or
   *                            PKCS#1 "BEGIN RSA PRIVATE KEY")
   * @param p_jku              Optional URL of the JWK set that holds the public key
   */
  procedure set_card_signing_key(
    p_endpoint_code   in varchar2,
    p_kid             in varchar2,
    p_private_key_pem in clob,
    p_jku             in varchar2 default null
  );

  -- ============================================================================
  -- Requests
  -- ============================================================================

  /*
   * Answers one HTTP request. Pure: reads no CGI variables and writes no output,
   * so tests and other HTTP front ends can call it.
   *
   * An agent run is one transaction: a run that completes commits the writes of
   * its tools (and with them the open transaction of the caller) before the task
   * shows COMPLETED; a run that fails rolls them back to the start of the run.
   *
   * @param p_endpoint_code  Code of the endpoint (URL segment)
   * @param p_route          c_route_card, c_route_jsonrpc or c_route_rest
   * @param p_method         HTTP method
   * @param p_path           REST path below <endpoint>/rest, e.g. 'message:send', 'tasks',
   *                         'tasks/<id>:cancel', 'tasks/<id>/pushNotificationConfigs/<cfg>'.
   *                         Null for the other routes
   * @param p_query_string   Query string without '?'
   * @param p_body           Request body
   * @param p_headers        Request headers, names in lowercase (a2a-version, x-api-key,
   *                         a2a-extensions, ...)
   * @param p_client_id      Authenticated client ID from the front end (ORDS :current_user),
   *                         used by auth mode c_auth_oauth2
   * @param p_request_url    Absolute URL of the request; used to build the URLs on the card
   *                         when the endpoint has no base_url
   * @return                 Status, content type and body
   */
  function process_request(
    p_endpoint_code in varchar2,
    p_route         in varchar2,
    p_method        in varchar2,
    p_path          in varchar2 default null,
    p_query_string  in varchar2 default null,
    p_body          in clob     default null,
    p_headers       in json_object_t default null,
    p_client_id     in varchar2 default null,
    p_request_url   in varchar2 default null
  ) return t_http_response;

  /*
   * ORDS entry point: reads the headers and the request URL from the CGI
   * environment, calls process_request and writes the response through htp.
   *
   * @param po_status  HTTP status; bind it to :status_code in the ORDS handler
   */
  procedure handle_request(
    p_endpoint_code in  varchar2,
    p_route         in  varchar2,
    p_method        in  varchar2,
    p_path          in  varchar2 default null,
    p_body          in  clob     default null,
    p_client_id     in  varchar2 default null,
    po_status       out number
  );

  /*
   * Runs an A2A task that was accepted with returnImmediately. Called by the
   * scheduler job that the request created; not meant for direct calls.
   *
   * Background runs: SendMessage with configuration.returnImmediately = true on
   * an endpoint with allow_async = Y inserts the task as SUBMITTED, creates a
   * one-off scheduler job (auto drop) that calls run_task, and returns the
   * SUBMITTED task at once. The task row, its push notification configuration
   * and the job are committed in autonomous transactions: the job sees them,
   * and the transaction of the caller stays open (create_job would commit it).
   * The schema needs the CREATE JOB privilege; without it the task is FAILED.
   * run_task moves the task to WORKING (a CANCELED task is left alone), runs
   * the agent the way a blocking call does, sets the final state and sends the
   * push notifications. With allow_async = N the hint is ignored and the call
   * blocks. SendStreamingMessage ignores the hint too: a stream follows the
   * task to its end.
   */
  procedure run_task(
    p_task_id in varchar2
  );

end uc_ai_a2a;
/
