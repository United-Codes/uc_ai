create or replace package body uc_ai_a2a as

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  c_ct_json  constant varchar2(30 char) := 'application/json';
  c_ct_rest  constant varchar2(30 char) := 'application/a2a+json';
  c_ct_sse   constant varchar2(30 char) := 'text/event-stream';

  c_binding_jsonrpc constant varchar2(10 char) := 'jsonrpc';
  c_binding_rest    constant varchar2(10 char) := 'rest';

  -- Max age of the agent card in a client cache, in seconds
  c_card_max_age constant pls_integer := 300;

  -- ORDS module that serves the endpoints
  c_default_module constant varchar2(30 char) := 'uc_ai_a2a';


  -- ==========================================================================
  -- Small helpers
  -- ==========================================================================

  function get_endpoint_row(
    p_code in varchar2
  ) return uc_ai_a2a_endpoints%rowtype
  as
    l_row uc_ai_a2a_endpoints%rowtype;
  begin
    l_row := uc_ai_a2a_core.get_endpoint(p_code);
    return l_row;
  exception
    when no_data_found then
      raise_application_error(c_err_endpoint_not_found, 'The A2A endpoint "' || p_code || '" does not exist.');
  end get_endpoint_row;


  function yes_no(
    p_value in boolean
  ) return varchar2
  as
  begin
    return case when p_value then 'Y' else 'N' end;
  end yes_no;


  function role_name(
    p_endpoint_code in varchar2
  ) return varchar2
  as
  begin
    return 'uc_ai_a2a_' || p_endpoint_code;
  end role_name;


  /*
   * The input parameter that a plain text message can fill: the one required
   * string property of the input schema. Null when there is not exactly one.
   */
  function infer_text_param(
    p_agent_code    in varchar2,
    p_agent_version in number
  ) return varchar2
  as
    l_agent    uc_ai_agents%rowtype;
    l_schema   json_object_t;
    l_required json_array_t;
    l_props    json_object_t;
    l_prop     json_object_t;
  begin
    l_agent := uc_ai_agents_api.get_agent(p_agent_code, p_agent_version);
    if l_agent.input_schema is null then
      return null;
    end if;

    l_schema   := json_object_t.parse(l_agent.input_schema);
    l_required := l_schema.get_array('required');
    l_props    := l_schema.get_object('properties');
    if l_required is null or l_props is null or l_required.get_size <> 1 then
      return null;
    end if;

    l_prop := l_props.get_object(l_required.get_string(0));
    if l_prop is not null and l_prop.get_string('type') = 'string' then
      return l_required.get_string(0);
    end if;

    return null;
  exception
    -- @dblinter ignore(G-5040): a schema that is not readable only costs the default; the setup call still works
    when others then
      -- Without a usable schema there is no default; the setup call still works
      return null;
  end infer_text_param;


  -- ==========================================================================
  -- ORDS (every call goes through dynamic SQL: the package must compile
  -- without ORDS)
  -- ==========================================================================

  -- Runs one anonymous block with the ORDS or OAuth API. A block that does not
  -- compile means that the API is not there.
  -- @dblinter ignore(G-9501): every block is a literal of this package; only its bind values come from callers
  procedure run_ords_block(
    p_block in varchar2,
    p_bind1 in varchar2 default null,
    p_bind2 in varchar2 default null,
    p_bind3 in varchar2 default null,
    p_bind4 in clob     default null
  )
  as
    e_plsql_error exception;
    e_no_object   exception;
    pragma exception_init(e_plsql_error, -6550);
    pragma exception_init(e_no_object, -942);
  begin
    if p_bind4 is not null then
      execute immediate p_block using p_bind1, p_bind2, p_bind3, p_bind4;
    elsif p_bind3 is not null then
      execute immediate p_block using p_bind1, p_bind2, p_bind3;
    elsif p_bind2 is not null then
      execute immediate p_block using p_bind1, p_bind2;
    else
      execute immediate p_block using p_bind1;
    end if;
  exception
    when e_plsql_error or e_no_object then
      raise_application_error(
        c_err_ords_missing
      , 'ORDS is not available to this schema. Install ORDS, REST-enable the schema (ords.enable_schema) and grant execute on ords and oauth.'
      );
  end run_ords_block;


  -- The base path of the ORDS module without slashes, e.g. a2a
  function get_ords_base_path(
    p_module_name in varchar2 default c_default_module
  ) return varchar2
  as
    c_sql    constant varchar2(200 char) := 'select uri_prefix from user_ords_modules where name = :1';
    l_prefix varchar2(255 char);
  begin
    execute immediate c_sql into l_prefix using p_module_name;
    return trim(both '/' from l_prefix);
  exception
    -- @dblinter ignore(G-5040): no module yet, or no ORDS at all: the answer is the default of install_ords_module
    when others then
      return 'a2a';
  end get_ords_base_path;


  function ords_module_exists(
    p_module_name in varchar2 default c_default_module
  ) return boolean
  as
    c_sql   constant varchar2(200 char) := 'select count(*) from user_ords_modules where name = :1';
    l_count pls_integer;
  begin
    execute immediate c_sql into l_count using p_module_name;
    return l_count > 0;
  exception
    -- @dblinter ignore(G-5040): without ORDS there is no module; that is the answer, not a failure
    when others then
      return false;
  end ords_module_exists;


  -- Runs a block of the ORDS API whose failure does not matter: it deletes
  -- something that may not exist, or creates something that may exist. Only a
  -- missing ORDS is an error.
  procedure run_ords_block_quiet(
    p_block in varchar2,
    p_bind1 in varchar2 default null,
    p_bind2 in varchar2 default null
  )
  as
    e_ords_missing exception;
    pragma exception_init(e_ords_missing, -20432);
  begin
    run_ords_block(p_block, p_bind1, p_bind2);
  exception
    when e_ords_missing then
      raise;
    -- @dblinter ignore(G-5040): the callers ask for "make sure it is gone / is there"; the state they want may exist already
    when others then
      null;
  end run_ords_block_quiet;


  -- The role, the privilege and the mapping that protect one OAuth2 endpoint
  procedure ensure_oauth_privilege(
    p_endpoint_code in varchar2,
    p_base_path     in varchar2
  )
  as
    l_name varchar2(200 char);
    l_path varchar2(300 char);
  begin
    l_name := role_name(p_endpoint_code);
    l_path := '/' || p_base_path || '/' || p_endpoint_code;

    run_ords_block_quiet('begin ords.create_role(p_role_name => :1); end;', l_name);

    -- Start from nothing: the mappings of an older run may differ
    run_ords_block_quiet(
      'begin ords.delete_privilege_mapping(p_privilege_name => :1, p_pattern => :2); end;'
    , l_name, l_path || '/jsonrpc');
    run_ords_block_quiet(
      'begin ords.delete_privilege_mapping(p_privilege_name => :1, p_pattern => :2); end;'
    , l_name, l_path || '/rest/*');
    run_ords_block_quiet('begin ords.delete_privilege(p_name => :1); end;', l_name);

    run_ords_block(
      'begin ords.create_privilege(p_name => :1, p_role_name => :2, p_label => :3, p_description => :4); end;'
    , l_name, l_name, 'UC AI A2A ' || p_endpoint_code
    , to_clob('Access to the A2A endpoint ' || p_endpoint_code));
    run_ords_block(
      'begin ords.create_privilege_mapping(p_privilege_name => :1, p_pattern => :2); end;'
    , l_name, l_path || '/jsonrpc');
    run_ords_block(
      'begin ords.create_privilege_mapping(p_privilege_name => :1, p_pattern => :2); end;'
    , l_name, l_path || '/rest/*');
  end ensure_oauth_privilege;


  procedure drop_oauth_privilege(
    p_endpoint_code in varchar2,
    p_base_path     in varchar2
  )
  as
    l_name varchar2(200 char);
    l_path varchar2(300 char);
  begin
    l_name := role_name(p_endpoint_code);
    l_path := '/' || p_base_path || '/' || p_endpoint_code;

    run_ords_block_quiet(
      'begin ords.delete_privilege_mapping(p_privilege_name => :1, p_pattern => :2); end;'
    , l_name, l_path || '/jsonrpc');
    run_ords_block_quiet(
      'begin ords.delete_privilege_mapping(p_privilege_name => :1, p_pattern => :2); end;'
    , l_name, l_path || '/rest/*');
    run_ords_block_quiet('begin ords.delete_privilege(p_name => :1); end;', l_name);
    run_ords_block_quiet('begin ords.delete_role(p_role_name => :1); end;', l_name);
  end drop_oauth_privilege;


  -- The source of one ORDS handler
  function handler_source(
    p_route     in varchar2,
    p_method    in varchar2,
    p_path_expr in varchar2,
    p_with_body in boolean
  ) return varchar2
  as
  begin
    return 'declare'                                                      || chr(10)
        || '  l_status number;'                                           || chr(10)
        || 'begin'                                                        || chr(10)
        || '  uc_ai_a2a.handle_request('                                  || chr(10)
        || '    p_endpoint_code => :ep'                                   || chr(10)
        || '  , p_route         => ''' || p_route || ''''                 || chr(10)
        || '  , p_method        => ''' || p_method || ''''                || chr(10)
        || '  , p_path          => ' || p_path_expr                       || chr(10)
        || '  , p_body          => ' || case when p_with_body then ':body_text' else 'null' end || chr(10)
        || '  , p_client_id     => :current_user'                         || chr(10)
        || '  , po_status       => l_status'                              || chr(10)
        || '  );'                                                         || chr(10)
        || '  :status_code := l_status;'                                  || chr(10)
        || 'end;';
  end handler_source;


  procedure define_handler(
    p_module_name in varchar2,
    p_pattern     in varchar2,
    p_method      in varchar2,
    p_route       in varchar2,
    p_path_expr   in varchar2
  )
  as
  begin
    run_ords_block(
      q'[begin
           ords.define_handler(
             p_module_name    => :1
           , p_pattern        => :2
           , p_method         => :3
           , p_source_type    => ords.source_type_plsql
           , p_items_per_page => 0
           , p_source         => :4
           );
         end;]'
    , p_module_name
    , p_pattern
    , p_method
    , handler_source(p_route, p_method, p_path_expr, p_method in ('POST', 'PUT'))
    );
  end define_handler;


  procedure define_template(
    p_module_name in varchar2,
    p_pattern     in varchar2
  )
  as
  begin
    run_ords_block(
      'begin ords.define_template(p_module_name => :1, p_pattern => :2); end;'
    , p_module_name
    , p_pattern
    );
  end define_template;


  procedure install_ords_module(
    p_base_path   in varchar2 default 'a2a/',
    p_module_name in varchar2 default 'uc_ai_a2a'
  )
  as
    l_scope     uc_ai_logger.scope := gc_scope_prefix || 'install_ords_module';
    l_base_path varchar2(255 char);
  begin
    l_base_path := trim(both '/' from p_base_path) || '/';
    uc_ai_logger.log('Installing the ORDS module ' || p_module_name, l_scope);

    -- Recreate: the module is generated code and holds nothing of its own
    run_ords_block_quiet('begin ords.delete_module(p_module_name => :1); end;', p_module_name);

    run_ords_block(
      q'[begin
           ords.define_module(
             p_module_name    => :1
           , p_base_path      => :2
           , p_items_per_page => 0
           , p_status         => 'PUBLISHED'
           );
         end;]'
    , p_module_name
    , l_base_path
    );

    -- The agent card
    define_template(p_module_name, ':ep/.well-known/agent-card.json');
    define_handler(p_module_name, ':ep/.well-known/agent-card.json', 'GET', c_route_card, 'null');

    -- JSON-RPC binding
    define_template(p_module_name, ':ep/jsonrpc');
    define_handler(p_module_name, ':ep/jsonrpc', 'POST', c_route_jsonrpc, 'null');

    -- REST binding. A literal colon is not allowed in a template pattern, so
    -- ":send", ":cancel" and ":subscribe" arrive as the end of a parameter.
    define_template(p_module_name, ':ep/rest/:op');
    define_handler(p_module_name, ':ep/rest/:op', 'POST', c_route_rest, ':op');
    define_handler(p_module_name, ':ep/rest/:op', 'GET', c_route_rest, ':op');

    define_template(p_module_name, ':ep/rest/tasks');
    define_handler(p_module_name, ':ep/rest/tasks', 'GET', c_route_rest, '''tasks''');

    define_template(p_module_name, ':ep/rest/tasks/:id');
    define_handler(p_module_name, ':ep/rest/tasks/:id', 'GET', c_route_rest, '''tasks/'' || :id');
    define_handler(p_module_name, ':ep/rest/tasks/:id', 'POST', c_route_rest, '''tasks/'' || :id');

    define_template(p_module_name, ':ep/rest/tasks/:id/pushNotificationConfigs');
    define_handler(p_module_name, ':ep/rest/tasks/:id/pushNotificationConfigs', 'GET', c_route_rest,
                   '''tasks/'' || :id || ''/pushNotificationConfigs''');
    define_handler(p_module_name, ':ep/rest/tasks/:id/pushNotificationConfigs', 'POST', c_route_rest,
                   '''tasks/'' || :id || ''/pushNotificationConfigs''');

    define_template(p_module_name, ':ep/rest/tasks/:id/pushNotificationConfigs/:cfg');
    define_handler(p_module_name, ':ep/rest/tasks/:id/pushNotificationConfigs/:cfg', 'GET', c_route_rest,
                   '''tasks/'' || :id || ''/pushNotificationConfigs/'' || :cfg');
    define_handler(p_module_name, ':ep/rest/tasks/:id/pushNotificationConfigs/:cfg', 'DELETE', c_route_rest,
                   '''tasks/'' || :id || ''/pushNotificationConfigs/'' || :cfg');

    -- The endpoints that use OAuth2 need their privilege
    <<install_privileges_loop>>
    for l_ep in (select code from uc_ai_a2a_endpoints where auth_mode = c_auth_oauth2) loop
      ensure_oauth_privilege(l_ep.code, trim(both '/' from l_base_path));
    end loop install_privileges_loop;

    commit;
  exception
    when others then
      uc_ai_logger.log_error(
        'Error installing the ORDS module',
        l_scope,
        sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
      raise;
  end install_ords_module;


  procedure uninstall_ords_module(
    p_module_name in varchar2 default 'uc_ai_a2a'
  )
  as
    l_scope     uc_ai_logger.scope := gc_scope_prefix || 'uninstall_ords_module';
    l_base_path varchar2(255 char);
  begin
    l_base_path := get_ords_base_path(p_module_name);
    uc_ai_logger.log('Removing the ORDS module ' || p_module_name, l_scope);

    <<uninstall_privileges_loop>>
    for l_ep in (select code from uc_ai_a2a_endpoints where auth_mode = c_auth_oauth2) loop
      drop_oauth_privilege(l_ep.code, l_base_path);
    end loop uninstall_privileges_loop;

    run_ords_block('begin ords.delete_module(p_module_name => :1); end;', p_module_name);
    commit;
  end uninstall_ords_module;


  procedure create_oauth_client(
    p_endpoint_code  in  varchar2,
    p_client_name    in  varchar2,
    p_support_email  in  varchar2,
    po_client_id     out varchar2,
    po_client_secret out varchar2
  )
  as
    c_sql      constant varchar2(200 char) := 'select client_id, client_secret from user_ords_clients where name = :1';
    l_endpoint uc_ai_a2a_endpoints%rowtype;
    l_role     varchar2(200 char);
  begin
    l_endpoint := get_endpoint_row(p_endpoint_code);
    if l_endpoint.auth_mode <> c_auth_oauth2 then
      raise_application_error(
        c_err_invalid_endpoint
      , 'The endpoint "' || p_endpoint_code || '" does not use OAuth2 (auth mode ' || l_endpoint.auth_mode || ').'
      );
    end if;

    l_role := role_name(p_endpoint_code);
    ensure_oauth_privilege(p_endpoint_code, get_ords_base_path);

    run_ords_block(
      q'[begin
           oauth.create_client(
             p_name            => :1
           , p_grant_type      => 'client_credentials'
           , p_owner           => user
           , p_description     => :2
           , p_support_email   => :3
           , p_privilege_names => :4
           );
         end;]'
    , p_client_name
    , 'A2A client of the endpoint ' || p_endpoint_code
    , p_support_email
    , to_clob(l_role)
    );
    run_ords_block(
      'begin oauth.grant_client_role(p_client_name => :1, p_role_name => :2); end;'
    , p_client_name
    , l_role
    );

    execute immediate c_sql into po_client_id, po_client_secret using p_client_name;

    commit;
  end create_oauth_client;


  -- ==========================================================================
  -- Endpoints
  -- ==========================================================================

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
  ) return number
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'expose_agent';
    l_id         uc_ai_a2a_endpoints.id%type;
    l_count      pls_integer;
    l_text_param uc_ai_a2a_endpoints.text_input_param%type;
    l_extras     json_object_t;
    l_el         json_element_t;
    e_not_json   exception;
    pragma exception_init(e_not_json, -40441);
    l_files      varchar2(1 char);
    l_async      varchar2(1 char);
  begin
    l_files := yes_no(p_accept_files);
    l_async := yes_no(p_allow_async);

    if p_code is null or not regexp_like(p_code, '^[a-z0-9][a-z0-9_-]*$') or length(p_code) > 100 then
      raise_application_error(
        c_err_invalid_endpoint
      , 'The endpoint code must be 1 to 100 characters: lowercase letters, digits, "_" and "-", starting with a letter or digit.'
      );
    end if;

    if p_auth_mode is null or p_auth_mode not in (c_auth_api_key, c_auth_oauth2, c_auth_none) then
      raise_application_error(c_err_invalid_endpoint, 'The auth mode must be api_key, oauth2 or none.');
    end if;

    select case when exists (
             select 1
               from uc_ai_agents
              where code = p_agent_code
                and ((p_agent_version is null and status = uc_ai_agents_api.c_status_active)
                  or version = p_agent_version)
           ) then 1 else 0 end
      into l_count
      from dual;
    if l_count = 0 then
      raise_application_error(
        c_err_invalid_endpoint
      , 'The agent "' || p_agent_code || '" does not exist'
        || case when p_agent_version is null then ' or has no active version.' else ' in version ' || p_agent_version || '.' end
      );
    end if;

    if p_card_extras is not null then
      begin
        l_extras := json_object_t.parse(p_card_extras);
        l_el     := l_extras.get('provider');
        if l_el is not null and not l_el.is_object then
          raise_application_error(c_err_invalid_endpoint, 'p_card_extras: provider must be an object.');
        end if;
        l_el := l_extras.get('tags');
        if l_el is not null and not l_el.is_array then
          raise_application_error(c_err_invalid_endpoint, 'p_card_extras: tags must be an array.');
        end if;
        l_el := l_extras.get('examples');
        if l_el is not null and not l_el.is_array then
          raise_application_error(c_err_invalid_endpoint, 'p_card_extras: examples must be an array.');
        end if;
      exception
        when e_not_json then
          raise_application_error(c_err_invalid_endpoint, 'p_card_extras must be a JSON object.');
      end;
    end if;

    l_text_param := coalesce(p_text_input_param, infer_text_param(p_agent_code, p_agent_version));

    update uc_ai_a2a_endpoints
       set agent_code       = p_agent_code,
           agent_version    = p_agent_version,
           name             = coalesce(p_name, p_agent_code),
           description      = p_description,
           card_version     = coalesce(p_card_version, '1.0.0'),
           text_input_param = l_text_param,
           auth_mode        = p_auth_mode,
           accept_files     = l_files,
           allow_async      = l_async,
           base_url         = p_base_url,
           card_extras      = p_card_extras,
           updated_by       = coalesce(sys_context('APEX$SESSION', 'APP_USER'), user),
           updated_at       = systimestamp
     where code = p_code
    returning id into l_id;

    if sql%rowcount = 0 then
      insert into uc_ai_a2a_endpoints (
        code, agent_code, agent_version, name, description, card_version, text_input_param
      , auth_mode, accept_files, allow_async, base_url, card_extras
      ) values (
        p_code, p_agent_code, p_agent_version, coalesce(p_name, p_agent_code), p_description
      , coalesce(p_card_version, '1.0.0'), l_text_param
      , p_auth_mode, l_files, l_async, p_base_url, p_card_extras
      )
      returning id into l_id;
    end if;

    -- The privilege of an OAuth2 endpoint is part of the ORDS setup
    if p_auth_mode = c_auth_oauth2 and ords_module_exists then
      ensure_oauth_privilege(p_code, get_ords_base_path);
    end if;

    uc_ai_logger.log('Exposed agent ' || p_agent_code || ' as A2A endpoint ' || p_code, l_scope);
    return l_id;
  exception
    when others then
      uc_ai_logger.log_error(
        'Error exposing the agent',
        l_scope,
        sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
      raise;
  end expose_agent;


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
  )
  as
    l_id number;
  begin
    l_id := expose_agent(
      p_code             => p_code
    , p_agent_code       => p_agent_code
    , p_agent_version    => p_agent_version
    , p_name             => p_name
    , p_description      => p_description
    , p_text_input_param => p_text_input_param
    , p_auth_mode        => p_auth_mode
    , p_accept_files     => p_accept_files
    , p_allow_async      => p_allow_async
    , p_card_version     => p_card_version
    , p_base_url         => p_base_url
    , p_card_extras      => p_card_extras
    );
  end expose_agent;


  procedure set_enabled(
    p_code    in varchar2,
    p_enabled in boolean
  )
  as
    l_enabled varchar2(1 char);
  begin
    l_enabled := yes_no(p_enabled);
    update uc_ai_a2a_endpoints
       set enabled    = l_enabled,
           updated_by = coalesce(sys_context('APEX$SESSION', 'APP_USER'), user),
           updated_at = systimestamp
     where code = p_code;

    if sql%rowcount = 0 then
      raise_application_error(c_err_endpoint_not_found, 'The A2A endpoint "' || p_code || '" does not exist.');
    end if;
  end set_enabled;


  procedure remove_endpoint(
    p_code in varchar2
  )
  as
    l_endpoint uc_ai_a2a_endpoints%rowtype;
  begin
    l_endpoint := get_endpoint_row(p_code);

    -- Keys, tasks and push configurations go with the endpoint (on delete cascade)
    delete from uc_ai_a2a_endpoints where id = l_endpoint.id;

    if l_endpoint.auth_mode = c_auth_oauth2 then
      drop_oauth_privilege(p_code, get_ords_base_path);
    end if;
  end remove_endpoint;


  -- ==========================================================================
  -- API keys
  -- ==========================================================================

  function create_api_key(
    p_endpoint_code in varchar2,
    p_client_name   in varchar2,
    p_expires_at    in timestamp default null
  ) return varchar2
  as
    l_endpoint uc_ai_a2a_endpoints%rowtype;
    c_sql      constant varchar2(200 char) := 'begin :1 := lower(rawtohex(sys.dbms_crypto.randombytes(24))); end;';
    l_hex      varchar2(48 char);
    l_key      varchar2(60 char);
    l_count    pls_integer;
  begin
    l_endpoint := get_endpoint_row(p_endpoint_code);

    if p_client_name is null then
      raise_application_error(c_err_api_key, 'The client name is required.');
    end if;

    select case when exists (
             select 1
               from uc_ai_a2a_api_keys
              where endpoint_id = l_endpoint.id
                and client_name = p_client_name
                and revoked_at is null
           ) then 1 else 0 end
      into l_count
      from dual;
    if l_count = 1 then
      raise_application_error(
        c_err_api_key
      , 'The client "' || p_client_name || '" has a key already. Revoke it first.'
      );
    end if;

    begin
      execute immediate c_sql using out l_hex;
    exception
      -- @dblinter ignore(G-5040): any failure of the call means that dbms_crypto is not usable; the error says what to grant
      when others then
        raise_application_error(
          c_err_crypto_missing
        , 'Creating an API key needs execute on dbms_crypto. Run as SYS: grant execute on sys.dbms_crypto to '
          || user || ';'
        );
    end;
    l_key := 'a2a_' || l_hex;

    -- A revoked key of the same client name makes room for the new one
    delete from uc_ai_a2a_api_keys
     where endpoint_id = l_endpoint.id
       and client_name = p_client_name;

    insert into uc_ai_a2a_api_keys (endpoint_id, client_name, key_prefix, key_hash, expires_at)
    values (
      l_endpoint.id
    , p_client_name
    , substr(l_key, 1, 8)
    , lower(rawtohex(standard_hash(l_key, 'SHA256')))
    , p_expires_at
    );

    return l_key;
  end create_api_key;


  procedure revoke_api_key(
    p_endpoint_code in varchar2,
    p_client_name   in varchar2
  )
  as
    l_endpoint uc_ai_a2a_endpoints%rowtype;
  begin
    l_endpoint := get_endpoint_row(p_endpoint_code);

    update uc_ai_a2a_api_keys
       set revoked_at = systimestamp
     where endpoint_id = l_endpoint.id
       and client_name = p_client_name
       and revoked_at is null;
  end revoke_api_key;


  -- Autonomous: a request is read-only for the caller's transaction
  procedure touch_api_key(
    p_key_id in number
  )
  as
    -- @dblinter ignore(G-3330): the key use is recorded even when the caller of a read-only request rolls back
    pragma autonomous_transaction;
  begin
    update uc_ai_a2a_api_keys
       set last_used_at = systimestamp
     where id = p_key_id;
    commit;
  exception
    when others then
      rollback;
      raise;
  end touch_api_key;


  /*
   * The client ID of a request, or the error c_err_unauthenticated.
   * api_key: the hash of the X-API-Key header must match a valid key of the
   * endpoint. oauth2: ORDS has done the work and hands the client over.
   */
  function authenticate(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_headers   in json_object_t,
    p_client_id in varchar2
  ) return varchar2
  as
    l_key       varchar2(4000 char);
    l_key_id    number;
    l_client    varchar2(255 char);
  begin
    case p_endpoint.auth_mode
      when c_auth_none then
        return 'anonymous';

      when c_auth_oauth2 then
        if p_client_id is null then
          uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_unauthenticated, 'Authentication is required.');
        end if;
        return substr(p_client_id, 1, 255);

      else
        if p_headers is not null then
          l_key := p_headers.get_string('x-api-key');
        end if;
        if l_key is null then
          uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_unauthenticated, 'Authentication is required.');
        end if;

        select id, client_name
          into l_key_id, l_client
          from uc_ai_a2a_api_keys
         where endpoint_id = p_endpoint.id
           and key_hash    = lower(rawtohex(standard_hash(l_key, 'SHA256')))
           and revoked_at is null
           and (expires_at is null or expires_at > localtimestamp);

        touch_api_key(l_key_id);
        return 'apikey:' || l_client;
    end case;
  exception
    when no_data_found then
      uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_unauthenticated, 'The API key is not valid.');
      return null;
  end authenticate;


  -- ==========================================================================
  -- Responses
  -- ==========================================================================

  function make_response(
    p_status       in pls_integer,
    p_content_type in varchar2,
    p_body         in clob
  ) return t_http_response
  as
    l_response t_http_response;
  begin
    l_response.status       := p_status;
    l_response.content_type := p_content_type;
    l_response.body         := p_body;
    return l_response;
  end make_response;


  -- The error object of a REST response, or the data of a JSON-RPC error: the
  -- ErrorInfo list
  function error_details(
    p_info in uc_ai_a2a_core.t_error_info
  ) return json_array_t
  as
    l_details json_array_t := json_array_t();
    l_detail  json_object_t;
  begin
    if p_info.reason is not null then
      l_detail := json_object_t();
      l_detail.put('@type', 'type.googleapis.com/google.rpc.ErrorInfo');
      l_detail.put('reason', p_info.reason);
      l_detail.put('domain', uc_ai_a2a_core.c_error_domain);
      l_details.append(l_detail);
    end if;
    return l_details;
  end error_details;


  function rest_error(
    p_info in uc_ai_a2a_core.t_error_info
  ) return t_http_response
  as
    l_body  json_object_t := json_object_t();
    l_error json_object_t := json_object_t();
  begin
    l_error.put('code', p_info.http_status);
    l_error.put('status', p_info.grpc_status);
    l_error.put('message', p_info.message);
    l_error.put('details', error_details(p_info));
    l_body.put('error', l_error);

    return make_response(p_info.http_status, c_ct_rest, l_body.to_clob);
  end rest_error;


  function jsonrpc_error(
    p_info in uc_ai_a2a_core.t_error_info,
    p_id   in json_element_t
  ) return t_http_response
  as
    l_body  json_object_t := json_object_t();
    l_error json_object_t := json_object_t();
  begin
    l_body.put('jsonrpc', '2.0');
    if p_id is null then
      l_body.put_null('id');
    else
      l_body.put('id', p_id);
    end if;

    l_error.put('code', p_info.jsonrpc_code);
    l_error.put('message', p_info.message);
    l_error.put('data', error_details(p_info));
    l_body.put('error', l_error);

    -- JSON-RPC errors travel in a 200 response; a caller that is not
    -- authenticated gets the HTTP status that tells it so
    return make_response(
      case when p_info.http_status = 401 then 401 else 200 end
    , c_ct_json
    , l_body.to_clob
    );
  end jsonrpc_error;


  -- The id of a JSON-RPC request, null when the body does not give one
  function try_get_id(
    p_body in clob
  ) return json_element_t
  as
    l_req json_object_t;
    l_id  json_element_t;
  begin
    if p_body is null then
      return null;
    end if;
    l_req := json_object_t.parse(p_body);
    l_id  := l_req.get('id');
    if l_id is not null and (l_id.is_string or l_id.is_number) then
      return l_id;
    end if;
    return null;
  exception
    -- @dblinter ignore(G-5040): a body without a readable id answers with a null id, as the JSON-RPC spec says
    when others then
      return null;
  end try_get_id;


  function not_found_response return t_http_response
  as
  begin
    return make_response(
      404
    , c_ct_json
    , '{"error":{"code":404,"status":"NOT_FOUND","message":"The A2A endpoint does not exist."}}'
    );
  end not_found_response;


  -- ==========================================================================
  -- URLs
  -- ==========================================================================

  /*
   * The public URL of the endpoint, without a trailing slash: the base_url of
   * the endpoint, else the request URL minus what the route adds to it.
   */
  function get_base_url(
    p_endpoint    in uc_ai_a2a_endpoints%rowtype,
    p_route       in varchar2,
    p_path        in varchar2,
    p_request_url in varchar2
  ) return varchar2
  as
    l_suffix varchar2(4000 char);
    l_url    varchar2(4000 char) := p_request_url;
  begin
    if p_endpoint.base_url is not null then
      return rtrim(p_endpoint.base_url, '/');
    end if;
    if l_url is null then
      return '/' || p_endpoint.code;
    end if;

    l_suffix := case p_route
                  when c_route_card    then '/.well-known/agent-card.json'
                  when c_route_jsonrpc then '/jsonrpc'
                  else '/rest' || case when p_path is not null then '/' || p_path end
                end;

    if substr(l_url, -length(l_suffix)) = l_suffix then
      return substr(l_url, 1, length(l_url) - length(l_suffix));
    end if;

    return regexp_replace(l_url, '/(\.well-known/agent-card\.json|jsonrpc|rest(/.*)?)$');
  end get_base_url;


  -- ==========================================================================
  -- Operations behind both bindings
  -- ==========================================================================

  -- Reads a query string into an object of strings
  function query_to_json(
    p_query in varchar2
  ) return json_object_t
  as
    l_params json_object_t := json_object_t();
    l_pair   varchar2(4000 char);
    l_pos    pls_integer;
    l_eq     pls_integer;
    l_start  pls_integer := 1;
    l_len    pls_integer;
  begin
    l_len := nvl(length(p_query), 0);
    <<query_pairs_loop>>
    while l_start <= l_len loop
      l_pos := instr(p_query, '&', l_start);
      if l_pos = 0 then
        l_pos := l_len + 1;
      end if;
      l_pair := substr(p_query, l_start, l_pos - l_start);
      l_eq   := instr(l_pair, '=');
      if l_eq > 1 then
        l_params.put(
          sys.utl_url.unescape(substr(l_pair, 1, l_eq - 1))
        , sys.utl_url.unescape(replace(substr(l_pair, l_eq + 1), '+', ' '))
        );
      end if;
      l_start := l_pos + 1;
    end loop query_pairs_loop;

    return l_params;
  end query_to_json;


  -- Events as Server-Sent Events. p_id is the JSON-RPC id; with no id the
  -- events go out as they are (REST).
  function events_to_sse(
    p_events  in json_array_t,
    p_binding in varchar2,
    p_id      in json_element_t
  ) return clob
  as
    l_body  clob;
    l_wrap  json_object_t;
  begin
    sys.dbms_lob.createtemporary(l_body, true);

    <<events_loop>>
    for i in 0 .. p_events.get_size - 1 loop
      if p_binding = c_binding_jsonrpc then
        l_wrap := json_object_t();
        l_wrap.put('jsonrpc', '2.0');
        if p_id is null then
          l_wrap.put_null('id');
        else
          l_wrap.put('id', p_id);
        end if;
        l_wrap.put('result', treat(p_events.get(i) as json_object_t));
        l_body := l_body || 'data: ' || l_wrap.to_clob || chr(10) || chr(10);
      else
        l_body := l_body || 'data: ' || p_events.get(i).to_clob || chr(10) || chr(10);
      end if;
    end loop events_loop;

    return l_body;
  end events_to_sse;


  -- JSON-RPC method names of the A2A 0.3 protocol: another protocol version
  function is_legacy_method(
    p_method in varchar2
  ) return boolean
  as
  begin
    return p_method in (
      'message/send', 'message/stream', 'tasks/get', 'tasks/cancel', 'tasks/resubscribe', 'tasks/list'
    , 'tasks/pushNotificationConfig/set', 'tasks/pushNotificationConfig/get'
    , 'tasks/pushNotificationConfig/list', 'tasks/pushNotificationConfig/delete'
    , 'agent/getAuthenticatedExtendedCard'
    );
  end is_legacy_method;


  /*
   * Runs one operation by its JSON-RPC method name. Streaming operations are
   * not here: they return events, not one object.
   */
  function run_operation(
    p_method    in varchar2,
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t,
    p_base_url  in varchar2
  ) return json_object_t
  as
  begin
    case p_method
      when 'SendMessage' then
        return uc_ai_a2a_core.send_message(p_endpoint, p_client_id, p_params);
      when 'GetTask' then
        return uc_ai_a2a_core.get_task(p_endpoint, p_client_id, p_params);
      when 'ListTasks' then
        return uc_ai_a2a_core.list_tasks(p_endpoint, p_client_id, p_params);
      when 'CancelTask' then
        return uc_ai_a2a_core.cancel_task(p_endpoint, p_client_id, p_params);
      when 'GetExtendedAgentCard' then
        return uc_ai_a2a_core.get_extended_agent_card(p_endpoint, p_base_url);
      when 'CreateTaskPushNotificationConfig' then
        return uc_ai_a2a_core.create_push_config(p_endpoint, p_client_id, p_params);
      when 'GetTaskPushNotificationConfig' then
        return uc_ai_a2a_core.get_push_config(p_endpoint, p_client_id, p_params);
      when 'ListTaskPushNotificationConfigs' then
        return uc_ai_a2a_core.list_push_configs(p_endpoint, p_client_id, p_params);
      else
        uc_ai_a2a_core.raise_error(
          uc_ai_a2a_core.c_err_method_not_found
        , 'The method "' || substr(p_method, 1, 100) || '" does not exist.'
        );
        return null;
    end case;
  end run_operation;


  -- ==========================================================================
  -- JSON-RPC binding
  -- ==========================================================================

  function handle_jsonrpc(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_method    in varchar2,
    p_body      in clob,
    p_base_url  in varchar2
  ) return t_http_response
  as
    l_req    json_object_t;
    l_id     json_element_t;
    l_method varchar2(200 char);
    l_params json_object_t;
    l_el     json_element_t;
    l_result json_object_t;
    l_out    json_object_t := json_object_t();
  begin
    if p_method <> 'POST' then
      uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_invalid_request, 'Use POST.');
    end if;

    begin
      l_req := json_object_t.parse(p_body);
    exception
      -- @dblinter ignore(G-5040): any parse failure is the JSON-RPC parse error; the parser text stays out of the response
      when others then
        uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_parse, 'The request is not valid JSON.');
    end;

    l_id := l_req.get('id');
    if l_id is not null and (l_id.is_null or not (l_id.is_string or l_id.is_number)) then
      l_id := null;
    end if;

    l_el := l_req.get('method');
    if nvl(l_req.get_string('jsonrpc'), '-') <> '2.0' or l_el is null or not l_el.is_string then
      uc_ai_a2a_core.raise_error(
        uc_ai_a2a_core.c_err_invalid_request
      , 'A JSON-RPC 2.0 request needs "jsonrpc": "2.0" and a "method".'
      );
    end if;
    l_method := substr(l_req.get_string('method'), 1, 200);

    l_el := l_req.get('params');
    if l_el is null or l_el.is_null then
      l_params := json_object_t();
    elsif l_el.is_object then
      l_params := treat(l_el as json_object_t);
    else
      uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_invalid_params, 'params must be an object.');
    end if;

    if is_legacy_method(l_method) then
      uc_ai_a2a_core.raise_error(
        uc_ai_a2a_core.c_err_version_not_supported
      , 'This agent speaks A2A 1.0. The method "' || l_method || '" belongs to an older version.'
      );
    end if;

    -- Streaming
    case l_method
      when 'SendStreamingMessage' then
        return make_response(
          200
        , c_ct_sse
        , events_to_sse(
            uc_ai_a2a_core.send_streaming_message(p_endpoint, p_client_id, l_params)
          , c_binding_jsonrpc, l_id)
        );
      when 'SubscribeToTask' then
        return make_response(
          200
        , c_ct_sse
        , events_to_sse(
            uc_ai_a2a_core.subscribe_to_task(p_endpoint, p_client_id, l_params)
          , c_binding_jsonrpc, l_id)
        );
      else
        null;
    end case;

    if l_method = 'DeleteTaskPushNotificationConfig' then
      l_result := uc_ai_a2a_core.delete_push_config(p_endpoint, p_client_id, l_params);
    else
      l_result := run_operation(l_method, p_endpoint, p_client_id, l_params, p_base_url);
    end if;

    l_out.put('jsonrpc', '2.0');
    if l_id is null then
      l_out.put_null('id');
    else
      l_out.put('id', l_id);
    end if;
    l_out.put('result', l_result);
    return make_response(200, c_ct_json, l_out.to_clob);
  end handle_jsonrpc;


  -- ==========================================================================
  -- REST binding
  -- ==========================================================================

  function parse_rest_body(
    p_body in clob
  ) return json_object_t
  as
  begin
    if p_body is null or sys.dbms_lob.getlength(p_body) = 0 then
      uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_invalid_request, 'The request needs a JSON body.');
    end if;

    begin
      return json_object_t.parse(p_body);
    exception
      -- @dblinter ignore(G-5040): any parse failure is the parse error of the binding; the parser text stays out of the response
      when others then
        uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_parse, 'The request is not valid JSON.');
        return null;
    end;
  end parse_rest_body;


  function handle_rest(
    p_endpoint     in uc_ai_a2a_endpoints%rowtype,
    p_client_id    in varchar2,
    p_method       in varchar2,
    p_path         in varchar2,
    p_query_string in varchar2,
    p_body         in clob,
    p_base_url     in varchar2
  ) return t_http_response
  as
    l_path   varchar2(4000 char);
    l_params json_object_t;
    l_id     varchar2(4000 char);
    l_cfg    varchar2(4000 char);
    l_tail   varchar2(4000 char);
    l_result json_object_t;
    c_not_found constant varchar2(200 char) := 'No operation for this path and method.';
  begin
    l_path := trim(both '/' from p_path);

    if l_path = 'message:send' or l_path = 'message:stream' then
      if p_method <> 'POST' then
        uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_method_not_found, c_not_found);
      end if;
      l_params := parse_rest_body(p_body);
      if l_path = 'message:send' then
        l_result := uc_ai_a2a_core.send_message(p_endpoint, p_client_id, l_params);
      else
        return make_response(
          200
        , c_ct_sse
        , events_to_sse(
            uc_ai_a2a_core.send_streaming_message(p_endpoint, p_client_id, l_params)
          , c_binding_rest, null)
        );
      end if;

    elsif l_path = 'extendedAgentCard' and p_method = 'GET' then
      l_result := run_operation('GetExtendedAgentCard', p_endpoint, p_client_id, null, p_base_url);

    elsif l_path = 'tasks' and p_method = 'GET' then
      l_result := uc_ai_a2a_core.list_tasks(p_endpoint, p_client_id, query_to_json(p_query_string));

    elsif regexp_like(l_path, '^tasks/[^/]+$') then
      l_tail := substr(l_path, 7);
      l_params := query_to_json(p_query_string);
      if regexp_like(l_tail, ':cancel$') and p_method = 'POST' then
        l_params.put('id', regexp_replace(l_tail, ':cancel$'));
        l_result := uc_ai_a2a_core.cancel_task(p_endpoint, p_client_id, l_params);
      elsif regexp_like(l_tail, ':subscribe$') and p_method in ('GET', 'POST') then
        l_params.put('id', regexp_replace(l_tail, ':subscribe$'));
        return make_response(
          200
        , c_ct_sse
        , events_to_sse(
            uc_ai_a2a_core.subscribe_to_task(p_endpoint, p_client_id, l_params)
          , c_binding_rest, null)
        );
      elsif p_method = 'GET' and instr(l_tail, ':') = 0 then
        l_params.put('id', l_tail);
        l_result := uc_ai_a2a_core.get_task(p_endpoint, p_client_id, l_params);
      else
        uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_method_not_found, c_not_found);
      end if;

    elsif regexp_like(l_path, '^tasks/[^/]+/pushNotificationConfigs$') then
      l_id := regexp_substr(l_path, '^tasks/([^/]+)/', 1, 1, null, 1);
      case p_method
        when 'POST' then
          l_params := parse_rest_body(p_body);
          l_params.put('taskId', l_id);
          l_result := uc_ai_a2a_core.create_push_config(p_endpoint, p_client_id, l_params);
        when 'GET' then
          l_params := query_to_json(p_query_string);
          l_params.put('taskId', l_id);
          l_result := uc_ai_a2a_core.list_push_configs(p_endpoint, p_client_id, l_params);
        else
          uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_method_not_found, c_not_found);
      end case;

    elsif regexp_like(l_path, '^tasks/[^/]+/pushNotificationConfigs/[^/]+$') then
      l_id  := regexp_substr(l_path, '^tasks/([^/]+)/', 1, 1, null, 1);
      l_cfg := regexp_substr(l_path, '/([^/]+)$', 1, 1, null, 1);
      l_params := json_object_t();
      l_params.put('taskId', l_id);
      l_params.put('id', l_cfg);
      case p_method
        when 'GET' then
          l_result := uc_ai_a2a_core.get_push_config(p_endpoint, p_client_id, l_params);
        when 'DELETE' then
          l_result := uc_ai_a2a_core.delete_push_config(p_endpoint, p_client_id, l_params);
        else
          uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_method_not_found, c_not_found);
      end case;

    else
      uc_ai_a2a_core.raise_error(uc_ai_a2a_core.c_err_method_not_found, c_not_found);
    end if;

    return make_response(200, c_ct_rest, l_result.to_clob);
  end handle_rest;


  -- ==========================================================================
  -- Requests
  -- ==========================================================================

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
  ) return t_http_response
  as
    l_scope    uc_ai_logger.scope := gc_scope_prefix || 'process_request';
    l_endpoint uc_ai_a2a_endpoints%rowtype;
    l_client   varchar2(255 char);
    l_base_url varchar2(4000 char);
    l_info     uc_ai_a2a_core.t_error_info;
    l_card     json_object_t;
  begin
    begin
      l_endpoint := uc_ai_a2a_core.get_endpoint(p_endpoint_code);
    exception
      when no_data_found then
        return not_found_response;
    end;
    if l_endpoint.enabled <> 'Y' then
      return not_found_response;
    end if;

    l_base_url := get_base_url(l_endpoint, p_route, p_path, p_request_url);

    -- The agent card is public
    if p_route = c_route_card then
      if p_method <> 'GET' then
        l_info := uc_ai_a2a_core.get_error_info(
                    uc_ai_a2a_core.c_err_method_not_found, 'ORA-20442: Use GET.');
        return rest_error(l_info);
      end if;
      l_card := uc_ai_a2a_core.build_agent_card(l_endpoint, l_base_url);
      return make_response(200, c_ct_json, l_card.to_clob);
    end if;

    if p_route not in (c_route_jsonrpc, c_route_rest) then
      return not_found_response;
    end if;

    uc_ai_a2a_core.check_version(case when p_headers is not null then p_headers.get_string('a2a-version') end);
    l_client := authenticate(l_endpoint, p_headers, p_client_id);

    if p_route = c_route_jsonrpc then
      return handle_jsonrpc(l_endpoint, l_client, p_method, p_body, l_base_url);
    end if;

    return handle_rest(l_endpoint, l_client, p_method, p_path, p_query_string, p_body, l_base_url);
  exception
    -- @dblinter ignore(G-5040): every error becomes the error response of the binding; the internal ones are logged here
    when others then
      l_info := uc_ai_a2a_core.get_error_info(sqlcode, sqlerrm);
      if l_info.jsonrpc_code = -32603 then
        uc_ai_logger.log_error(
          'Error answering an A2A request',
          l_scope,
          sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );
      end if;

      if p_route = c_route_jsonrpc then
        return jsonrpc_error(l_info, try_get_id(p_body));
      end if;
      return rest_error(l_info);
  end process_request;


  procedure write_clob(
    p_clob in clob
  )
  as
    c_chunk constant pls_integer := 8000;
    l_len   pls_integer;
    l_pos   pls_integer := 1;
  begin
    if p_clob is null then
      return;
    end if;

    l_len := sys.dbms_lob.getlength(p_clob);
    <<chunks_loop>>
    while l_pos <= l_len loop
      sys.htp.prn(sys.dbms_lob.substr(p_clob, c_chunk, l_pos));
      l_pos := l_pos + c_chunk;
    end loop chunks_loop;
  end write_clob;


  procedure handle_request(
    p_endpoint_code in  varchar2,
    p_route         in  varchar2,
    p_method        in  varchar2,
    p_path          in  varchar2 default null,
    p_body          in  clob     default null,
    p_client_id     in  varchar2 default null,
    po_status       out number
  )
  as
    l_headers  json_object_t := json_object_t();
    l_url      varchar2(4000 char);
    l_response t_http_response;
  begin
    l_headers.put('a2a-version', sys.owa_util.get_cgi_env('A2A-Version'));
    l_headers.put('x-api-key', sys.owa_util.get_cgi_env(c_api_key_header));
    l_headers.put('a2a-extensions', sys.owa_util.get_cgi_env('A2A-Extensions'));

    l_url := sys.owa_util.get_cgi_env('REQUEST_SCHEME') || '://' || sys.owa_util.get_cgi_env('HTTP_HOST')
          || sys.owa_util.get_cgi_env('SCRIPT_NAME') || sys.owa_util.get_cgi_env('PATH_INFO');

    l_response := process_request(
      p_endpoint_code => p_endpoint_code
    , p_route         => p_route
    , p_method        => p_method
    , p_path          => p_path
    , p_query_string  => sys.owa_util.get_cgi_env('QUERY_STRING')
    , p_body          => p_body
    , p_headers       => l_headers
    , p_client_id     => p_client_id
    , p_request_url   => l_url
    );

    po_status := l_response.status;

    sys.owa_util.mime_header(l_response.content_type, false, 'UTF-8');
    if p_route = c_route_card and l_response.status = 200 then
      sys.htp.p('Cache-Control: max-age=' || c_card_max_age);
    elsif l_response.content_type = c_ct_sse then
      sys.htp.p('Cache-Control: no-cache');
    end if;
    sys.owa_util.http_header_close;
    write_clob(l_response.body);
  end handle_request;


  -- ==========================================================================
  -- Later phases
  -- ==========================================================================

  procedure set_card_signing_key(
    p_endpoint_code   in varchar2,
    p_kid             in varchar2,
    p_private_key_pem in clob,
    p_jku             in varchar2 default null
  )
  as
    l_endpoint uc_ai_a2a_endpoints%rowtype;
  begin
    l_endpoint := get_endpoint_row(p_endpoint_code);

    if p_private_key_pem is null then
      update uc_ai_a2a_endpoints
         set signing_kid = null,
             signing_key = null,
             signing_jku = null,
             updated_by  = coalesce(sys_context('APEX$SESSION', 'APP_USER'), user),
             updated_at  = systimestamp
       where id = l_endpoint.id;
      return;
    end if;

    if p_kid is null then
      raise_application_error(c_err_signing, 'The key ID (p_kid) is required.');
    end if;

    -- Sign something once: a key that dbms_crypto does not accept fails here,
    -- not on the first request for the card
    if uc_ai_a2a_core.sign_rs256(p_private_key_pem, sys.utl_raw.cast_to_raw('probe')) is null then
      raise_application_error(c_err_signing, 'The key produced no signature.');
    end if;

    update uc_ai_a2a_endpoints
       set signing_kid = p_kid,
           signing_key = p_private_key_pem,
           signing_jku = p_jku,
           updated_by  = coalesce(sys_context('APEX$SESSION', 'APP_USER'), user),
           updated_at  = systimestamp
     where id = l_endpoint.id;
  end set_card_signing_key;


  procedure run_task(
    p_task_id in varchar2
  )
  as
  begin
    uc_ai_a2a_core.run_task(p_task_id);
  end run_task;

end uc_ai_a2a;
/
