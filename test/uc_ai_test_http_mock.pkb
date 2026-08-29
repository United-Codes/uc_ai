create or replace package body uc_ai_test_http_mock as

  type t_response is record (
    body        clob
  , status_code pls_integer
  );

  type t_requests  is table of t_request  index by pls_integer;
  type t_responses is table of t_response index by pls_integer;

  -- @dblinter ignore(g-9105): package-global collections; the g_ prefix is intended (not local vars)
  g_requests   t_requests;
  -- @dblinter ignore(g-9105): package-global collections; the g_ prefix is intended (not local vars)
  g_responses  t_responses;
  -- index of the next response to hand out
  g_next       pls_integer := 1;


  procedure reset
  as
  begin
    g_requests.delete;
    g_responses.delete;
    g_next := 1;
  end reset;


  procedure enqueue(
    p_body        in clob
  , p_status_code in pls_integer default 200
  )
  as
    l_response t_response;
  begin
    l_response.body        := p_body;
    l_response.status_code := p_status_code;
    g_responses(g_responses.count + 1) := l_response;
  end enqueue;


  function header_snapshot return json_object_t
  as
    l_headers json_object_t := json_object_t();
  begin
    <<header_loop>>
    for i in 1 .. apex_web_service.g_request_headers.count loop
      l_headers.put(lower(apex_web_service.g_request_headers(i).name), apex_web_service.g_request_headers(i).value);
    end loop header_loop;

    return l_headers;
  end header_snapshot;


  function post(
    p_url                  in varchar2
  , p_body                 in clob
  , p_credential_static_id in varchar2
  ) return clob
  as
    l_request  t_request;
    l_response t_response;
  begin
    l_request.url        := p_url;
    l_request.body       := p_body;
    l_request.credential := p_credential_static_id;
    l_request.headers    := header_snapshot;
    g_requests(g_requests.count + 1) := l_request;

    if not g_responses.exists(g_next) then
      raise_application_error(-20991,
        'uc_ai_test_http_mock: request ' || g_requests.count || ' to ' || p_url
        || ' arrived but no response is queued');
    end if;

    l_response := g_responses(g_next);
    g_next := g_next + 1;

    apex_web_service.g_status_code := l_response.status_code;

    return l_response.body;
  end post;


  function request_count return pls_integer
  as
  begin
    return g_requests.count;
  end request_count;


  function pending_count return pls_integer
  as
  begin
    return g_responses.count - (g_next - 1);
  end pending_count;


  function request(p_index in pls_integer) return t_request
  as
  begin
    if not g_requests.exists(p_index) then
      raise_application_error(-20992,
        'uc_ai_test_http_mock: no request ' || p_index || ' was recorded (' || g_requests.count || ' so far)');
    end if;

    return g_requests(p_index);
  end request;


  function request_json(p_index in pls_integer) return json_object_t
  as
  begin
    return json_object_t.parse(request(p_index).body);
  end request_json;


  function request_header(
    p_index in pls_integer
  , p_name  in varchar2
  ) return varchar2
  as
    l_headers json_object_t;
  begin
    l_headers := request(p_index).headers;

    if l_headers.has(lower(p_name)) then
      return l_headers.get_string(lower(p_name));
    end if;

    return null;
  end request_header;

end uc_ai_test_http_mock;
/
