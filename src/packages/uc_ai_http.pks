create or replace package uc_ai_http
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
   * The one place UC AI talks HTTP. Every provider sends its request body through
   * post(), so a test can register a replacement transport, read the exact body,
   * URL and headers that would have gone to the provider, and hand back a recorded
   * response (see test/uc_ai_test_http_mock and test/test_uc_ai_wire).
   *
   * Request headers keep travelling through apex_web_service.g_request_headers and
   * the HTTP status keeps arriving in apex_web_service.g_status_code, exactly as
   * before this package existed. A replacement transport has to honour both: read
   * the headers it needs from g_request_headers, and set g_status_code before it
   * returns, because uc_ai_error.parse_json_response reads it.
   *
   * Registering a transport is a TEST-ONLY facility and is compiled out of the
   * default build. See set_transport below.
   */

  /*
   * POST p_body to p_url and return the response body.
   * With no transport registered this is apex_web_service.make_rest_request.
   */
  function post(
    p_url                  in varchar2
  , p_body                 in clob
  , p_credential_static_id in varchar2 default null
  ) return clob;

  /*
   * Register a package that replaces apex_web_service for the rest of the session.
   * The package must expose a function with the signature of post() above:
   *
   *   function post(
   *     p_url                  in varchar2
   *   , p_body                 in clob
   *   , p_credential_static_id in varchar2
   *   ) return clob;
   *
   * Pass null to go back to apex_web_service. The registration is session-scoped
   * and uc_ai.reset_globals leaves it alone: like uc_ai.set_event_callback it is a
   * long-lived setup step, not a per-call setting.
   *
   * ONLY AVAILABLE IN A DEBUG BUILD. The body carries this procedure and the
   * dynamic call it needs behind `$if $$uc_ai_debug`, so an installed default
   * build cannot redirect a provider request at all: the code is not in it. In
   * that build set_transport raises -20502 and get_transport returns null.
   *
   * To enable it in a test schema (never in production):
   *   alter package uc_ai_http compile body plsql_ccflags = 'UC_AI_DEBUG:TRUE' reuse settings;
   * or run scripts/enable_test_transport.sql. Reinstalling or recompiling the
   * package without the flag turns it back off.
   */
  procedure set_transport(p_package_name in varchar2);

  /*
   * The registered transport package, or null when apex_web_service is in use.
   */
  function get_transport return varchar2;

end uc_ai_http;
/
