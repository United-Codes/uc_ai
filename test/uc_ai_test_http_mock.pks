create or replace package uc_ai_test_http_mock as

  -- Replacement HTTP transport for LLM-free tests.
  --
  -- Register it with uc_ai_http.set_transport('uc_ai_test_http_mock'). From then
  -- on every provider request lands in post() instead of apex_web_service: the
  -- URL, body, credential and a snapshot of apex_web_service.g_request_headers are
  -- recorded, and the next queued response is returned with its HTTP status
  -- written to apex_web_service.g_status_code, which is where
  -- uc_ai_error.parse_json_response reads it.
  --
  -- A request that arrives with an empty queue raises -20991, so a test that
  -- forgets a response, or a framework that makes one request too many, fails
  -- loudly instead of hanging on a null body.

  type t_request is record (
    url        varchar2(4000 char)
  , body       clob
  , credential varchar2(255 char)
    -- header name -> value, as apex_web_service.g_request_headers stood at send time
  , headers    json_object_t
  );

  -- Forget every recorded request and every queued response.
  procedure reset;

  -- Queue the response for the next request. Responses are consumed in order.
  procedure enqueue(
    p_body        in clob
  , p_status_code in pls_integer default 200
  );

  -- The transport. Called by uc_ai_http.post through the registration; a test
  -- never calls it directly.
  function post(
    p_url                  in varchar2
  , p_body                 in clob
  , p_credential_static_id in varchar2
  ) return clob;

  -- Number of requests recorded since the last reset.
  function request_count return pls_integer;

  -- Number of queued responses nobody asked for. Zero at the end of a test means
  -- the framework made exactly the requests the test expected.
  function pending_count return pls_integer;

  -- The p_index-th request (1-based).
  function request(p_index in pls_integer) return t_request;

  -- The body of the p_index-th request, parsed.
  function request_json(p_index in pls_integer) return json_object_t;

  -- One request header by name (case-insensitive); null when it was not sent.
  function request_header(
    p_index in pls_integer
  , p_name  in varchar2
  ) return varchar2;

end uc_ai_test_http_mock;
/
