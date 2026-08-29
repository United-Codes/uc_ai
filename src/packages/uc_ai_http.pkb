create or replace package body uc_ai_http as

  c_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  /*
   * The replaceable transport exists only in a build compiled with
   * UC_AI_DEBUG:TRUE. In the default build the code below is not compiled at all,
   * so post() reaches apex_web_service directly, there is no dynamic call and no
   * package state that could redirect a provider request.
   *
   * Enable it in a test schema with:
   *   alter package uc_ai_http compile body plsql_ccflags = 'UC_AI_DEBUG:TRUE' reuse settings;
   * (scripts/enable_test_transport.sql does this and reports what it did.)
   */
  $if $$uc_ai_debug $then

  -- The registered replacement transport; null means apex_web_service. Session
  -- state by design: see the spec.
  -- @dblinter ignore(g-7230): a transport registration is session-scoped by design, like uc_ai.g_event_callback
  g_transport varchar2(128 char);

  $end


  -- @dblinter ignore(g-7150): p_package_name is used in the $$uc_ai_debug branch, which the linter does not compile
  procedure set_transport(p_package_name in varchar2)
  as
  begin
    $if $$uc_ai_debug $then

    if p_package_name is null then
      g_transport := null;
    else
      -- validates [SCHEMA.]PACKAGE syntax; raises ORA-44003 on bad input
      g_transport := sys.dbms_assert.qualified_sql_name(p_package_name);
    end if;

    $else

    uc_ai_error.raise_error(
      p_error_code => uc_ai_error.c_err_missing_config
    , p_scope      => c_scope_prefix || 'set_transport'
    , p0           => 'uc_ai_http.set_transport'
    , p1           => q'!a build compiled with plsql_ccflags = 'UC_AI_DEBUG:TRUE'!'
    );

    $end
  end set_transport;


  function get_transport return varchar2
  as
  begin
    $if $$uc_ai_debug $then
    return g_transport;
    $else
    return null;
    $end
  end get_transport;


  function post(
    p_url                  in varchar2
  , p_body                 in clob
  , p_credential_static_id in varchar2 default null
  ) return clob
  as
    $if $$uc_ai_debug $then
    l_scope uc_ai_logger.scope := c_scope_prefix || 'post';
    l_resp  clob;
    l_stmt  varchar2(500 char);
    $end
  begin
    $if $$uc_ai_debug $then

    if g_transport is not null then
      uc_ai_logger.log('Sending through the registered transport ' || g_transport, l_scope, p_url);

      -- g_transport passed dbms_assert.qualified_sql_name in set_transport, so it
      -- is a plain identifier and safe to splice.
      l_stmt := 'begin :resp := ' || g_transport
        || '.post(p_url => :url, p_body => :body, p_credential_static_id => :cred); end;';

      execute immediate l_stmt
        using out l_resp, in p_url, in p_body, in p_credential_static_id;

      return l_resp;
    end if;

    $end

    return apex_web_service.make_rest_request(
      p_url                  => p_url
    , p_http_method          => 'POST'
    , p_body                 => p_body
    , p_credential_static_id => p_credential_static_id
    );
  end post;

end uc_ai_http;
/
