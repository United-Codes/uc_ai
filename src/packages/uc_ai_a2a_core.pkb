create or replace package body uc_ai_a2a_core as
  -- @dblinter ignore(G-7210): the operations of the protocol share the task, message and push helpers; splitting them would need another package that calls back into this one

  gc_scope_prefix constant varchar2(31 char) := lower($$plsql_unit) || '.';

  c_default_page_size constant pls_integer := 50;
  c_max_page_size     constant pls_integer := 100;

  -- Text of the status message of a failed task. The real error goes to the log.
  c_failed_text constant varchar2(100 char) := 'The agent run failed.';

  -- Longest wait of SubscribeToTask, in seconds
  c_subscribe_max_seconds constant pls_integer := 600;

  -- Timeout of one push notification request, in seconds
  c_push_timeout constant pls_integer := 15;

  -- Error code of the signing errors (the same as uc_ai_a2a.c_err_signing)
  c_err_signing constant number := -20435;

  -- The input of one agent run, taken from a client message
  type t_run is record (
    input     json_object_t,
    follow_up clob,
    files     uc_ai_message_api.t_files
  );


  -- ==========================================================================
  -- Errors
  -- ==========================================================================

  function get_error_info(
    p_sqlcode in number,
    p_sqlerrm in varchar2
  ) return t_error_info
  as
    l_info t_error_info;
    l_text varchar2(4000 char);
  begin
    -- "ORA-20450: text" -> "text", first line only
    l_text := regexp_replace(p_sqlerrm, '^ORA-[0-9]+: ');
    if instr(l_text, chr(10)) > 0 then
      l_text := substr(l_text, 1, instr(l_text, chr(10)) - 1);
    end if;
    l_info.message := l_text;

    case p_sqlcode
      when c_err_parse then
        l_info.jsonrpc_code := -32700;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'INVALID_ARGUMENT';
      when c_err_invalid_request then
        l_info.jsonrpc_code := -32600;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'INVALID_ARGUMENT';
      when c_err_method_not_found then
        l_info.jsonrpc_code := -32601;
        l_info.http_status  := 404;
        l_info.grpc_status  := 'NOT_FOUND';
      when c_err_invalid_params then
        l_info.jsonrpc_code := -32602;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'INVALID_ARGUMENT';
      when c_err_task_not_found then
        l_info.jsonrpc_code := -32001;
        l_info.http_status  := 404;
        l_info.grpc_status  := 'NOT_FOUND';
        l_info.reason       := 'TASK_NOT_FOUND';
      when c_err_task_not_cancelable then
        l_info.jsonrpc_code := -32002;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'FAILED_PRECONDITION';
        l_info.reason       := 'TASK_NOT_CANCELABLE';
      when c_err_push_not_supported then
        l_info.jsonrpc_code := -32003;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'FAILED_PRECONDITION';
        l_info.reason       := 'PUSH_NOTIFICATION_NOT_SUPPORTED';
      when c_err_unsupported_op then
        l_info.jsonrpc_code := -32004;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'FAILED_PRECONDITION';
        l_info.reason       := 'UNSUPPORTED_OPERATION';
      when c_err_content_type then
        l_info.jsonrpc_code := -32005;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'INVALID_ARGUMENT';
        l_info.reason       := 'CONTENT_TYPE_NOT_SUPPORTED';
      when c_err_invalid_agent_resp then
        l_info.jsonrpc_code := -32006;
        l_info.http_status  := 500;
        l_info.grpc_status  := 'INTERNAL';
        l_info.reason       := 'INVALID_AGENT_RESPONSE';
      when c_err_no_extended_card then
        l_info.jsonrpc_code := -32007;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'FAILED_PRECONDITION';
        l_info.reason       := 'EXTENDED_AGENT_CARD_NOT_CONFIGURED';
      when c_err_version_not_supported then
        l_info.jsonrpc_code := -32009;
        l_info.http_status  := 400;
        l_info.grpc_status  := 'FAILED_PRECONDITION';
        l_info.reason       := 'VERSION_NOT_SUPPORTED';
      when c_err_unauthenticated then
        l_info.jsonrpc_code := -32000;
        l_info.http_status  := 401;
        l_info.grpc_status  := 'UNAUTHENTICATED';
      else
        -- Anything else is a bug or an outage. The caller learns nothing about it.
        l_info.jsonrpc_code := -32603;
        l_info.http_status  := 500;
        l_info.grpc_status  := 'INTERNAL';
        l_info.message      := 'Internal error';
    end case;

    return l_info;
  end get_error_info;


  procedure raise_error(
    p_code    in number,
    p_message in varchar2
  )
  as
  begin
    raise_application_error(p_code, p_message);
  end raise_error;


  -- ==========================================================================
  -- Small helpers
  -- ==========================================================================

  function get_endpoint(
    p_code in varchar2
  ) return uc_ai_a2a_endpoints%rowtype
  as
    l_row uc_ai_a2a_endpoints%rowtype;
  begin
    select *
      into l_row
      from uc_ai_a2a_endpoints
     where code = p_code;

    return l_row;
  end get_endpoint;


  procedure check_version(
    p_version in varchar2
  )
  as
  begin
    -- A client without the header is accepted: a tool such as curl does not send it
    if p_version is not null and trim(p_version) not in ('1.0', '1') then
      raise_error(
        c_err_version_not_supported
      , 'This agent speaks A2A 1.0. The version "' || substr(p_version, 1, 50) || '" is not supported.'
      );
    end if;
  end check_version;


  function is_terminal(
    p_state in varchar2
  ) return boolean
  as
  begin
    return p_state in (c_state_completed, c_state_failed, c_state_canceled, c_state_rejected);
  end is_terminal;


  function new_uuid return varchar2
  as
    l_hex varchar2(32 char);
  begin
    -- sys_guid alone is nearly sequential: hash it together with random noise
    select lower(substr(rawtohex(standard_hash(
             rawtohex(sys_guid()) || to_char(sys.dbms_random.value) || to_char(systimestamp), 'SHA256')), 1, 32))
      into l_hex
      from dual;

    -- Version 4 and the RFC 4122 variant
    return substr(l_hex, 1, 8) || '-' || substr(l_hex, 9, 4) || '-4' || substr(l_hex, 14, 3)
        || '-8' || substr(l_hex, 18, 3) || '-' || substr(l_hex, 21, 12);
  end new_uuid;


  -- ISO 8601, UTC. Every timestamp of the tables is stored in UTC.
  function iso(
    p_ts in timestamp
  ) return varchar2
  as
  begin
    return to_char(p_ts, 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"');
  end iso;


  function utc_now return timestamp
  as
  begin
    return sys_extract_utc(systimestamp);
  end utc_now;


  -- A string value of an object, null when the key is missing or not a string
  function get_str(
    p_obj in json_object_t,
    p_key in varchar2
  ) return clob
  as
    l_el json_element_t;
  begin
    l_el := p_obj.get(p_key);
    if l_el is null or not l_el.is_string then
      return null;
    end if;

    return p_obj.get_clob(p_key);
  end get_str;


  -- A number value. A string that holds a number counts too: the REST binding
  -- reads its parameters from a query string.
  function get_num(
    p_obj in json_object_t,
    p_key in varchar2
  ) return number
  as
    l_el json_element_t;
  begin
    l_el := p_obj.get(p_key);
    if l_el is null or l_el.is_null then
      return null;
    elsif l_el.is_number then
      return p_obj.get_number(p_key);
    elsif l_el.is_string then
      return to_number(p_obj.get_string(p_key));
    end if;

    raise_error(c_err_invalid_params, p_key || ' must be a number.');
    return null;
  exception
    when value_error then
      raise_error(c_err_invalid_params, p_key || ' must be a number.');
      return null;
  end get_num;


  function get_bool(
    p_obj     in json_object_t,
    p_key     in varchar2,
    p_default in boolean
  ) return boolean
  as
    l_el json_element_t;
  begin
    l_el := p_obj.get(p_key);
    if l_el is null or l_el.is_null then
      return p_default;
    elsif l_el.is_boolean then
      return p_obj.get_boolean(p_key);
    elsif l_el.is_string and lower(p_obj.get_string(p_key)) in ('true', 'false') then
      return lower(p_obj.get_string(p_key)) = 'true';
    end if;

    raise_error(c_err_invalid_params, p_key || ' must be true or false.');
    return p_default;
  end get_bool;


  -- The history length of a request: null (all), or 0 and more
  function get_history_length(
    p_params in json_object_t
  ) return number
  as
    l_len number;
  begin
    l_len := get_num(p_params, 'historyLength');
    if l_len is not null and (l_len < 0 or l_len <> trunc(l_len)) then
      raise_error(c_err_invalid_params, 'historyLength must be a whole number of 0 or more.');
    end if;

    return l_len;
  end get_history_length;


  function get_required_id(
    p_params in json_object_t,
    p_key    in varchar2 default 'id'
  ) return varchar2
  as
    l_id varchar2(4000 char);
  begin
    l_id := get_str(p_params, p_key);
    if l_id is null then
      raise_error(c_err_invalid_params, p_key || ' is required.');
    end if;

    return l_id;
  end get_required_id;


  function get_extras(
    p_endpoint in uc_ai_a2a_endpoints%rowtype
  ) return json_object_t
  as
  begin
    if p_endpoint.card_extras is null or sys.dbms_lob.getlength(p_endpoint.card_extras) = 0 then
      return json_object_t();
    end if;

    return json_object_t.parse(p_endpoint.card_extras);
  end get_extras;


  function get_token_url(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    p_base_url in varchar2
  ) return varchar2
  as
    l_extras json_object_t;
  begin
    l_extras := get_extras(p_endpoint);
    if get_str(l_extras, 'oauthTokenUrl') is not null then
      return l_extras.get_string('oauthTokenUrl');
    end if;

    return regexp_replace(p_base_url, '/[^/]+/[^/]+$') || '/oauth/token';
  end get_token_url;


  -- A text part
  function text_part(
    p_text in clob
  ) return json_object_t
  as
    l_part json_object_t := json_object_t();
  begin
    l_part.put('text', p_text);
    l_part.put('mediaType', 'text/plain');
    return l_part;
  end text_part;


  -- A message of the agent (role ROLE_AGENT)
  function agent_message(
    p_message_id in varchar2,
    p_context_id in varchar2,
    p_task_id    in varchar2,
    p_parts      in json_array_t
  ) return json_object_t
  as
    l_msg json_object_t := json_object_t();
  begin
    l_msg.put('messageId', p_message_id);
    l_msg.put('contextId', p_context_id);
    l_msg.put('taskId', p_task_id);
    l_msg.put('role', 'ROLE_AGENT');
    l_msg.put('parts', p_parts);
    return l_msg;
  end agent_message;


  -- ==========================================================================
  -- Task persistence. Every state change of a task goes through set_task_state.
  -- ==========================================================================

  -- Autonomous: another session (a GetTask call, a scheduler job) sees the task
  -- while the agent still runs.
  procedure insert_task(
    p_row in uc_ai_a2a_tasks%rowtype
  )
  as
    -- @dblinter ignore(G-3330): the task row must be visible to other sessions (GetTask, scheduler jobs) while the agent still runs
    pragma autonomous_transaction;
  begin
    insert into uc_ai_a2a_tasks values p_row;
    commit;
  exception
    when others then
      rollback;
      raise;
  end insert_task;


  /*
   * Moves a task to a new state. A task in a terminal state stays as it is: a
   * result that arrives after a cancel does not undo the cancel.
   * p_result and p_execution_id keep their stored value when null.
   */
  procedure set_task_state(
    p_task_id        in varchar2,
    p_state          in varchar2,
    p_status_message in varchar2 default null,
    p_result         in clob     default null,
    p_execution_id   in number   default null
  )
  as
    -- @dblinter ignore(G-3330): a state change must be visible to other sessions at once, whatever the caller's transaction does
    pragma autonomous_transaction;
  begin
    update uc_ai_a2a_tasks
       set state          = p_state,
           status_message = p_status_message,
           result         = coalesce(p_result, result),
           execution_id   = coalesce(p_execution_id, execution_id),
           pending_request = case when p_state <> c_state_submitted then null else pending_request end,
           updated_at     = sys_extract_utc(systimestamp)
     where task_id = p_task_id
       and state not in (c_state_completed, c_state_failed, c_state_canceled, c_state_rejected);
    commit;
  exception
    when others then
      rollback;
      raise;
  end set_task_state;


  -- Sends the push notifications of a task (defined with the push code below)
  procedure deliver_push_notifications(
    p_task_id   in varchar2,
    p_config_id in varchar2 default null
  );


  /*
   * Moves a task from SUBMITTED to WORKING. False when the task is not SUBMITTED
   * any more (canceled, or taken by another run): the caller must not run it.
   */
  function claim_task(
    p_task_id in varchar2
  ) return boolean
  as
    -- @dblinter ignore(G-3330): the new state must be visible to CancelTask and GetTask at once
    pragma autonomous_transaction;
    l_count pls_integer;
  begin
    update uc_ai_a2a_tasks
       set state           = c_state_working,
           pending_request = null,
           updated_at      = sys_extract_utc(systimestamp)
     where task_id = p_task_id
       and state   = c_state_submitted;
    l_count := sql%rowcount;
    commit;
    return l_count > 0;
  exception
    when others then
      rollback;
      raise;
  end claim_task;


  /*
   * The one place where a task ends: sets the final state, then tells the clients
   * that asked for a push notification.
   */
  procedure finish_task(
    p_task_id        in varchar2,
    p_state          in varchar2,
    p_status_message in varchar2 default null,
    p_result         in clob     default null,
    p_execution_id   in number   default null
  )
  as
  begin
    set_task_state(
      p_task_id        => p_task_id
    , p_state          => p_state
    , p_status_message => p_status_message
    , p_result         => p_result
    , p_execution_id   => p_execution_id
    );

    deliver_push_notifications(p_task_id);
  end finish_task;


  -- The task of this client, or the error that a missing task gives
  function get_owned_task(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_task_id   in varchar2
  ) return uc_ai_a2a_tasks%rowtype
  as
    l_row uc_ai_a2a_tasks%rowtype;
  begin
    select *
      into l_row
      from uc_ai_a2a_tasks
     where task_id     = p_task_id
       and endpoint_id = p_endpoint.id
       and client_id   = p_client_id;

    return l_row;
  exception
    when no_data_found then
      raise_error(c_err_task_not_found, 'The task does not exist.');
  end get_owned_task;


  -- ==========================================================================
  -- Task as JSON
  -- ==========================================================================

  function status_json(
    p_row in uc_ai_a2a_tasks%rowtype
  ) return json_object_t
  as
    l_status json_object_t := json_object_t();
    l_parts  json_array_t;
  begin
    l_status.put('state', p_row.state);
    if p_row.status_message is not null then
      l_parts := json_array_t();
      l_parts.append(text_part(p_row.status_message));
      l_status.put(
        'message'
      , agent_message(p_row.task_id || '-status', p_row.context_id, p_row.task_id, l_parts)
      );
    end if;
    l_status.put('timestamp', iso(p_row.updated_at));

    return l_status;
  end status_json;


  -- Token usage of the run, all nested runs included. Null when nothing is known.
  function usage_json(
    p_execution_id in number
  ) return json_object_t
  as
    l_in    number;
    l_out   number;
    l_usage json_object_t;
  begin
    if p_execution_id is null then
      return null;
    end if;

    select sum(total_input_tokens), sum(total_output_tokens)
      into l_in, l_out
      from uc_ai_agent_executions
     start with id = p_execution_id
   connect by prior id = parent_execution_id;

    if nvl(l_in, 0) + nvl(l_out, 0) = 0 then
      return null;
    end if;

    l_usage := json_object_t();
    l_usage.put('inputTokens', nvl(l_in, 0));
    l_usage.put('outputTokens', nvl(l_out, 0));
    return l_usage;
  end usage_json;


  function task_json(
    p_row               in uc_ai_a2a_tasks%rowtype,
    p_history_length    in number  default null,
    p_include_artifacts in boolean default true
  ) return json_object_t
  as
    l_task     json_object_t := json_object_t();
    l_artifact json_object_t;
    l_arts     json_array_t;
    l_history  json_array_t := json_array_t();
    l_limited  json_array_t := json_array_t();
    l_msg_parts json_array_t;
    l_usage    json_object_t;
    l_metadata json_object_t;
    l_start    pls_integer;
  begin
    l_task.put('id', p_row.task_id);
    l_task.put('contextId', p_row.context_id);
    l_task.put('status', status_json(p_row));

    if p_row.result is not null and p_include_artifacts then
      l_arts := json_array_t();
      l_arts.append(json_object_t.parse(p_row.result));
      l_task.put('artifacts', l_arts);
    end if;

    -- History: the client message, and the answer of the agent once there is one
    if p_row.request_message is not null then
      l_history.append(json_object_t.parse(p_row.request_message));
    end if;
    if p_row.result is not null and p_row.state = c_state_completed then
      l_artifact  := json_object_t.parse(p_row.result);
      l_msg_parts := l_artifact.get_array('parts');
      l_history.append(
        agent_message(p_row.task_id || '-reply', p_row.context_id, p_row.task_id, l_msg_parts)
      );
    end if;

    if p_history_length is null then
      l_limited := l_history;
    elsif p_history_length > 0 then
      l_start := greatest(l_history.get_size - p_history_length, 0);
      <<history_loop>>
      for i in l_start .. l_history.get_size - 1 loop
        l_limited.append(l_history.get(i));
      end loop history_loop;
    end if;
    if l_limited.get_size > 0 then
      l_task.put('history', l_limited);
    end if;

    l_usage := usage_json(p_row.execution_id);
    if l_usage is not null then
      l_metadata := json_object_t();
      l_metadata.put('usage', l_usage);
      l_task.put('metadata', l_metadata);
    end if;

    return l_task;
  end task_json;


  -- ==========================================================================
  -- Push notifications
  -- ==========================================================================

  procedure require_push_support(
    p_endpoint in uc_ai_a2a_endpoints%rowtype
  )
  as
  begin
    if p_endpoint.allow_async <> 'Y' then
      raise_error(c_err_push_not_supported, 'This agent does not support push notifications.');
    end if;
  end require_push_support;


  -- A configuration as the client sees it: TaskPushNotificationConfig
  function push_config_json(
    p_cfg in uc_ai_a2a_push_configs%rowtype
  ) return json_object_t
  as
    l_json json_object_t := json_object_t();
    l_auth json_object_t;
  begin
    l_json.put('id', p_cfg.config_id);
    l_json.put('taskId', p_cfg.task_id);
    l_json.put('url', p_cfg.url);
    if p_cfg.token is not null then
      l_json.put('token', p_cfg.token);
    end if;
    if p_cfg.auth_scheme is not null then
      l_auth := json_object_t();
      l_auth.put('scheme', p_cfg.auth_scheme);
      if p_cfg.auth_credentials is not null then
        l_auth.put('credentials', p_cfg.auth_credentials);
      end if;
      l_json.put('authentication', l_auth);
    end if;

    return l_json;
  end push_config_json;


  -- Makes sure that a TaskPushNotificationConfig is usable
  procedure check_push_config(
    p_config in json_object_t
  )
  as
    l_url  varchar2(4001 char);
    l_el   json_element_t;
    l_auth json_object_t;
  begin
    if p_config is null then
      raise_error(c_err_invalid_params, 'The push notification configuration is required.');
    end if;

    l_url := sys.dbms_lob.substr(get_str(p_config, 'url'), 4001, 1);
    if l_url is null then
      raise_error(c_err_invalid_params, 'url is required.');
    elsif length(l_url) > 4000 or not regexp_like(l_url, '^https?://[^[:space:]]+$', 'i') then
      raise_error(c_err_invalid_params, 'url must be an http or https URL of up to 4000 characters.');
    end if;

    l_el := p_config.get('token');
    if l_el is not null and not l_el.is_null
       and (not l_el.is_string or length(p_config.get_string('token')) > 4000) then
      raise_error(c_err_invalid_params, 'token must be a string of up to 4000 characters.');
    end if;

    l_el := p_config.get('id');
    if l_el is not null and not l_el.is_null
       and (not l_el.is_string or not regexp_like(p_config.get_string('id'), '^[A-Za-z0-9._:-]{1,255}$')) then
      raise_error(c_err_invalid_params, 'id must be 1 to 255 characters: letters, digits and . _ : -');
    end if;

    l_el := p_config.get('authentication');
    if l_el is not null and not l_el.is_null then
      if not l_el.is_object then
        raise_error(c_err_invalid_params, 'authentication must be an object.');
      end if;
      l_auth := treat(l_el as json_object_t);
      if get_str(l_auth, 'scheme') is null or length(l_auth.get_string('scheme')) > 100 then
        raise_error(c_err_invalid_params, 'authentication.scheme is required (up to 100 characters).');
      end if;
      l_el := l_auth.get('credentials');
      if l_el is not null and not l_el.is_null
         and (not l_el.is_string or length(l_auth.get_string('credentials')) > 4000) then
        raise_error(c_err_invalid_params, 'authentication.credentials must be a string of up to 4000 characters.');
      end if;
    end if;
  end check_push_config;


  -- Autonomous: a job or a later request must see the configuration at once
  procedure insert_push_config(
    p_row in uc_ai_a2a_push_configs%rowtype
  )
  as
    -- @dblinter ignore(G-3330): the configuration must be there when the task ends, whatever the caller's transaction does
    pragma autonomous_transaction;
  begin
    insert into uc_ai_a2a_push_configs values p_row;
    commit;
  exception
    when others then
      rollback;
      raise;
  end insert_push_config;


  procedure delete_push_config_row(
    p_task_id   in varchar2,
    p_config_id in varchar2
  )
  as
    -- @dblinter ignore(G-3330): a deleted configuration must not receive a notification that is sent after the delete
    pragma autonomous_transaction;
  begin
    delete from uc_ai_a2a_push_configs
     where task_id   = p_task_id
       and config_id = p_config_id;
    commit;
  exception
    when others then
      rollback;
      raise;
  end delete_push_config_row;


  -- Records the result of one delivery
  procedure record_delivery(
    p_id     in varchar2,
    p_status in number,
    p_error  in varchar2
  )
  as
    -- @dblinter ignore(G-3330): the record of a delivery must survive the transaction of the caller
    pragma autonomous_transaction;
  begin
    update uc_ai_a2a_push_configs
       set last_status     = p_status,
           last_error      = substr(p_error, 1, 4000),
           last_attempt_at = sys_extract_utc(systimestamp)
     where id = p_id;
    commit;
  exception
    when others then
      rollback;
      raise;
  end record_delivery;


  -- The row of a configuration, built from a TaskPushNotificationConfig
  function new_push_row(
    p_task_id in varchar2,
    p_config  in json_object_t
  ) return uc_ai_a2a_push_configs%rowtype
  as
    l_row  uc_ai_a2a_push_configs%rowtype;
    l_auth json_object_t;
  begin
    check_push_config(p_config);

    l_row.id         := new_uuid();
    l_row.task_id    := p_task_id;
    l_row.config_id  := coalesce(get_str(p_config, 'id'), l_row.id);
    l_row.url        := sys.dbms_lob.substr(get_str(p_config, 'url'), 4000, 1);
    l_row.token      := sys.dbms_lob.substr(get_str(p_config, 'token'), 4000, 1);
    l_auth           := p_config.get_object('authentication');
    if l_auth is not null then
      l_row.auth_scheme      := sys.dbms_lob.substr(get_str(l_auth, 'scheme'), 100, 1);
      l_row.auth_credentials := sys.dbms_lob.substr(get_str(l_auth, 'credentials'), 4000, 1);
    end if;
    l_row.created_at := utc_now();

    return l_row;
  end new_push_row;


  -- Stores a configuration. The task is known to belong to the caller.
  procedure store_push_row(
    p_row in uc_ai_a2a_push_configs%rowtype
  )
  as
  begin
    insert_push_config(p_row);
  exception
    when dup_val_on_index then
      raise_error(c_err_invalid_params, 'This task has a push notification configuration with this id already.');
  end store_push_row;


  /*
   * Sends the task, as a StreamResponse {"task": ...}, to every webhook of the
   * task. Headers: Content-Type, X-A2A-Notification-Token (when the
   * configuration has a token) and Authorization (when it has authentication).
   * The result of each delivery goes to last_status / last_error; an error is
   * never raised. With p_config_id only that configuration (its row id) is sent.
   */
  procedure deliver_push_notifications(
    p_task_id   in varchar2,
    p_config_id in varchar2 default null
  )
  as
    l_scope  uc_ai_logger.scope := gc_scope_prefix || 'deliver_push_notifications';
    l_row    uc_ai_a2a_tasks%rowtype;
    l_body   clob;
    l_resp   clob;
    l_status number;
    l_count  pls_integer;
    l_event  json_object_t;
  begin
    select case when exists (
             select 1
               from uc_ai_a2a_push_configs
              where task_id = p_task_id
                and (p_config_id is null or id = p_config_id)
           ) then 1 else 0 end
      into l_count
      from dual;
    if l_count = 0 then
      return;
    end if;

    select *
      into l_row
      from uc_ai_a2a_tasks
     where task_id = p_task_id;

    l_event := json_object_t();
    l_event.put('task', task_json(l_row));
    l_body := l_event.to_clob;

    <<webhooks_loop>>
    for l_cfg in (
      select id, url, token, auth_scheme, auth_credentials
        from uc_ai_a2a_push_configs
       where task_id = p_task_id
         and (p_config_id is null or id = p_config_id)
       order by created_at, id
    ) loop
      begin
        -- The HTTP package of APEX needs an APEX session. A run has made one; a cancel has not.
        uc_ai_agent_exec_api.create_apex_session_if_needed;

        apex_web_service.g_request_headers.delete;
        apex_web_service.g_request_headers(1).name  := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/a2a+json';
        if l_cfg.token is not null then
          apex_web_service.g_request_headers(apex_web_service.g_request_headers.count + 1).name  := 'X-A2A-Notification-Token';
          apex_web_service.g_request_headers(apex_web_service.g_request_headers.count).value := l_cfg.token;
        end if;
        if l_cfg.auth_scheme is not null then
          apex_web_service.g_request_headers(apex_web_service.g_request_headers.count + 1).name  := 'Authorization';
          apex_web_service.g_request_headers(apex_web_service.g_request_headers.count).value :=
            trim(l_cfg.auth_scheme || ' ' || l_cfg.auth_credentials);
        end if;

        l_resp   := uc_ai_http.post(l_cfg.url, l_body, null, c_push_timeout);
        l_status := apex_web_service.g_status_code;
        uc_ai_logger.log('Push notification sent to a webhook of task ' || p_task_id, l_scope, 'HTTP ' || l_status || ' ' || substr(l_resp, 1, 500));
        apex_web_service.g_request_headers.delete;

        record_delivery(
          l_cfg.id
        , l_status
        , case when l_status >= 300 then 'The webhook answered with HTTP ' || l_status end
        );
      exception
        -- @dblinter ignore(G-5040): a webhook that fails must not fail the task or the request; the error is recorded and logged
        when others then
          uc_ai_logger.log_error(
            'Push notification of task ' || p_task_id || ' failed',
            l_scope,
            sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
          );
          record_delivery(l_cfg.id, null, sqlerrm);
      end;
    end loop webhooks_loop;
  exception
    -- @dblinter ignore(G-5040): delivery is best effort; a failure here is logged and never reaches the caller
    when others then
      uc_ai_logger.log_error(
        'Push notifications of task ' || p_task_id || ' failed',
        l_scope,
        sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
  end deliver_push_notifications;


  -- ==========================================================================
  -- Card signing (JWS, RS256, over the RFC 8785 canonical form of the card)
  -- ==========================================================================

  -- RFC 8785 string: the escapes of ECMAScript JSON.stringify
  function jcs_quote(
    p_text in clob
  ) return clob
  as
    l_text clob := p_text;
    c_bs            constant varchar2(1 char) := chr(92);
    c_first_control constant pls_integer := 1;
    c_last_control  constant pls_integer := 31;
  begin
    l_text := replace(l_text, c_bs, c_bs || c_bs);
    l_text := replace(l_text, '"', c_bs || '"');
    l_text := replace(l_text, chr(8), c_bs || 'b');
    l_text := replace(l_text, chr(9), c_bs || 't');
    l_text := replace(l_text, chr(10), c_bs || 'n');
    l_text := replace(l_text, chr(12), c_bs || 'f');
    l_text := replace(l_text, chr(13), c_bs || 'r');
    <<control_loop>>
    for i in c_first_control .. c_last_control loop
      if i not in (8, 9, 10, 12, 13) then
        l_text := replace(l_text, chr(i), c_bs || 'u' || lpad(lower(to_char(i, 'fmxx')), 4, '0'));
      end if;
    end loop control_loop;

    return '"' || l_text || '"';
  end jcs_quote;


  /*
   * The canonical JSON of a card, as the A2A SDK verifier builds it: empty
   * strings, arrays and objects are left out, keys are sorted by code unit,
   * there is no white space. Null when the value is empty.
   */
  function canonical_json(
    p_el in json_element_t
  ) return clob
  as
    l_obj   json_object_t;
    l_arr   json_array_t;
    l_keys  json_key_list;
    l_key   varchar2(4000 char);
    l_out   clob;
    l_part  clob;
    l_text  clob;
    l_first boolean := true;
    l_pos   pls_integer;
  begin
    if p_el is null then
      return null;
    end if;

    if p_el.is_object then
      l_obj  := treat(p_el as json_object_t);
      l_keys := l_obj.get_keys;

      -- Insertion sort by the bytes of the key (UTF-8 order equals UTF-16 order for the BMP)
      <<sort_outer_loop>>
      for i in 1 .. l_keys.count loop
        l_key := l_keys(i);
        l_pos := i - 1;
        <<sort_inner_loop>>
        while l_pos >= 1 and sys.utl_raw.cast_to_raw(l_keys(l_pos)) > sys.utl_raw.cast_to_raw(l_key) loop
          l_keys(l_pos + 1) := l_keys(l_pos);
          l_pos := l_pos - 1;
        end loop sort_inner_loop;
        l_keys(l_pos + 1) := l_key;
      end loop sort_outer_loop;

      <<keys_loop>>
      for i in 1 .. l_keys.count loop
        l_part := canonical_json(l_obj.get(l_keys(i)));
        if l_part is not null then
          if not l_first then
            l_out := l_out || ',';
          end if;
          l_first := false;
          l_out := l_out || jcs_quote(l_keys(i)) || ':' || l_part;
        end if;
      end loop keys_loop;

      return case when l_out is not null then '{' || l_out || '}' end;

    elsif p_el.is_array then
      l_arr := treat(p_el as json_array_t);

      <<items_loop>>
      for i in 0 .. l_arr.get_size - 1 loop
        l_part := canonical_json(l_arr.get(i));
        if l_part is not null then
          if not l_first then
            l_out := l_out || ',';
          end if;
          l_first := false;
          l_out := l_out || l_part;
        end if;
      end loop items_loop;

      return case when l_out is not null then '[' || l_out || ']' end;

    elsif p_el.is_string then
      l_text := p_el.to_clob;
      return case when l_text is not null then jcs_quote(l_text) end;

    elsif p_el.is_boolean then
      return p_el.to_string;

    elsif p_el.is_number then
      -- A card holds no numbers; an integer is the only form that needs no ECMAScript formatting
      return to_char(p_el.to_number, 'TM9');
    end if;

    return null;
  end canonical_json;


  -- The text of a PEM key without header, footer and white space
  function pem_body(
    p_pem in clob
  ) return varchar2
  as
    l_pem varchar2(32000 char);
  begin
    l_pem := sys.dbms_lob.substr(p_pem, 32000, 1);
    if l_pem is null or instr(l_pem, 'PRIVATE KEY') = 0 or instr(l_pem, 'ENCRYPTED') > 0 then
      raise_error(c_err_signing, 'The key must be an unencrypted RSA private key in PEM form (BEGIN PRIVATE KEY or BEGIN RSA PRIVATE KEY).');
    end if;

    l_pem := regexp_replace(l_pem, '-----[A-Z ]+-----');
    return regexp_replace(l_pem, '[[:space:]]');
  end pem_body;


  /*
   * RSASSA-PKCS1-v1_5 with SHA-256 through dbms_crypto.sign (Oracle 21c or
   * later). dbms_crypto wants the key as the ASCII bytes of its base64 text
   * (the PEM body): both PKCS#8 and PKCS#1 work.
   */
  function sign_rs256(
    p_private_key_pem in clob,
    p_data            in raw
  ) return raw
  as
    -- 1 = DBMS_CRYPTO.KEY_TYPE_RSA, 2 = DBMS_CRYPTO.SIGN_SHA256_RSA
    c_sql constant varchar2(200 char) := 'begin :1 := sys.dbms_crypto.sign(:2, :3, 1, 2); end;';
    l_sig raw(4000);
    l_key raw(32000);
    e_signing exception;
    pragma exception_init(e_signing, -20435);
  begin
    l_key := sys.utl_raw.cast_to_raw(pem_body(p_private_key_pem));
    execute immediate c_sql using out l_sig, in p_data, in l_key;
    return l_sig;
  exception
    when e_signing then
      raise;
    when others then
      raise_error(
        c_err_signing
      , 'dbms_crypto.sign did not accept the key. It needs Oracle 21c or later, execute on sys.dbms_crypto, and an RSA private key without a password.'
      );
      return null;
  end sign_rs256;


  -- base64url (RFC 4648 section 5, no padding) of a text, as UTF-8
  function b64url(
    p_text in clob
  ) return clob
  as
    l_blob blob;
    l_dest integer := 1;
    l_src  integer := 1;
    l_lang integer := sys.dbms_lob.default_lang_ctx;
    l_warn integer;
    l_b64  clob;
  begin
    sys.dbms_lob.createtemporary(l_blob, true);
    sys.dbms_lob.converttoblob(
      dest_lob     => l_blob
    , src_clob     => p_text
    , amount       => sys.dbms_lob.lobmaxsize
    , dest_offset  => l_dest
    , src_offset   => l_src
    , blob_csid    => nls_charset_id('AL32UTF8')
    , lang_context => l_lang
    , warning      => l_warn
    );

    l_b64 := apex_web_service.blob2clobbase64(l_blob);
    sys.dbms_lob.freetemporary(l_blob);

    l_b64 := replace(replace(l_b64, chr(10)), chr(13));
    return rtrim(translate(l_b64, '+/', '-_'), '=');
  end b64url;


  -- Adds the signature of an endpoint to a card. A card that cannot be signed
  -- goes out without one: the error is logged, and a client that checks
  -- signatures refuses the card.
  procedure add_signature(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    pio_card   in out nocopy json_object_t
  )
  as
    l_scope     uc_ai_logger.scope := gc_scope_prefix || 'add_signature';
    l_header    json_object_t := json_object_t();
    l_canonical clob;
    l_protected clob;
    l_payload   clob;
    l_input     varchar2(32767 char);
    l_signature raw(4000);
    l_sig_b64   clob;
    l_entry     json_object_t := json_object_t();
    l_list      json_array_t := json_array_t();
  begin
    if p_endpoint.signing_key is null then
      return;
    end if;

    l_canonical := canonical_json(pio_card);

    l_header.put('alg', 'RS256');
    l_header.put('typ', 'JOSE');
    l_header.put('kid', p_endpoint.signing_kid);
    if p_endpoint.signing_jku is not null then
      l_header.put('jku', p_endpoint.signing_jku);
    end if;

    l_protected := b64url(l_header.to_clob);
    l_payload   := b64url(l_canonical);
    l_input     := l_protected || '.' || l_payload;
    l_signature := sign_rs256(p_endpoint.signing_key, sys.utl_raw.cast_to_raw(l_input));

    -- base64 of the signature bytes, through the same routine as the payload
    l_sig_b64 := rtrim(translate(
                   replace(replace(
                     sys.utl_raw.cast_to_varchar2(sys.utl_encode.base64_encode(l_signature))
                   , chr(10)), chr(13))
                 , '+/', '-_'), '=');

    l_entry.put('protected', l_protected);
    l_entry.put('signature', l_sig_b64);
    l_list.append(l_entry);
    pio_card.put('signatures', l_list);
  exception
    -- @dblinter ignore(G-5040): an unsigned card is better than no card; the cause is logged
    when others then
      uc_ai_logger.log_error(
        'Could not sign the card of endpoint ' || p_endpoint.code,
        l_scope,
        sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
  end add_signature;


  -- ==========================================================================
  -- Agent card
  -- ==========================================================================

  function build_agent_card(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    p_base_url in varchar2,
    p_extended in boolean default false
  ) return json_object_t
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'build_agent_card';
    l_agent      uc_ai_agents%rowtype;
    l_extras     json_object_t;
    l_card       json_object_t := json_object_t();
    l_ifaces     json_array_t  := json_array_t();
    l_iface      json_object_t;
    l_caps       json_object_t := json_object_t();
    l_in_modes   json_array_t  := json_array_t();
    l_out_modes  json_array_t  := json_array_t();
    l_skills     json_array_t  := json_array_t();
    l_skill      json_object_t := json_object_t();
    l_tags       json_array_t;
    l_description clob;
    l_scheme     json_object_t;
    l_flow       json_object_t;
    l_schemes    json_object_t;
    l_req        json_object_t;
    l_req_list   json_array_t;
    l_empty      json_object_t;
    l_el         json_element_t;
    l_provider   json_object_t;
  begin
    l_agent  := uc_ai_agents_api.get_agent(p_endpoint.agent_code, p_endpoint.agent_version);
    l_extras := get_extras(p_endpoint);

    l_description := coalesce(p_endpoint.description, l_agent.description);

    l_card.put('name', p_endpoint.name);
    l_card.put('description', l_description);
    l_card.put('version', p_endpoint.card_version);

    -- The two bindings this server speaks
    l_iface := json_object_t();
    l_iface.put('url', p_base_url || '/jsonrpc');
    l_iface.put('protocolBinding', 'JSONRPC');
    l_iface.put('protocolVersion', '1.0');
    l_ifaces.append(l_iface);
    l_iface := json_object_t();
    l_iface.put('url', p_base_url || '/rest');
    l_iface.put('protocolBinding', 'HTTP+JSON');
    l_iface.put('protocolVersion', '1.0');
    l_ifaces.append(l_iface);
    l_card.put('supportedInterfaces', l_ifaces);

    l_el := l_extras.get('provider');
    if l_el is not null and l_el.is_object then
      -- Only the fields of the proto AgentProvider: the signature covers the known fields
      l_provider := json_object_t();
      l_provider.put('organization', treat(l_el as json_object_t).get_string('organization'));
      l_provider.put('url', treat(l_el as json_object_t).get_string('url'));
      l_card.put('provider', l_provider);
    end if;
    if get_str(l_extras, 'documentationUrl') is not null then
      l_card.put('documentationUrl', l_extras.get_string('documentationUrl'));
    end if;
    if get_str(l_extras, 'iconUrl') is not null then
      l_card.put('iconUrl', l_extras.get_string('iconUrl'));
    end if;

    l_caps.put('streaming', true);
    l_caps.put('pushNotifications', p_endpoint.allow_async = 'Y');
    l_caps.put('extendedAgentCard', p_endpoint.auth_mode <> 'none');
    l_card.put('capabilities', l_caps);

    -- Authentication
    case p_endpoint.auth_mode
    when 'api_key' then
      l_scheme := json_object_t();
      l_scheme.put('location', 'header');
      l_scheme.put('name', 'X-API-Key');
      l_schemes := json_object_t();
      l_req := json_object_t();
      l_req.put('apiKeySecurityScheme', l_scheme);
      l_schemes.put('apiKey', l_req);
      l_card.put('securitySchemes', l_schemes);

      l_empty := json_object_t();
      l_empty.put('list', json_array_t());
      l_req := json_object_t();
      l_req.put('apiKey', l_empty);
      l_scheme := json_object_t();
      l_scheme.put('schemes', l_req);
      l_req_list := json_array_t();
      l_req_list.append(l_scheme);
      l_card.put('securityRequirements', l_req_list);
    when 'oauth2' then
      l_flow := json_object_t();
      l_flow.put('tokenUrl', get_token_url(p_endpoint, p_base_url));
      l_flow.put('scopes', json_object_t());
      l_scheme := json_object_t();
      l_scheme.put('clientCredentials', l_flow);
      l_flow := json_object_t();
      l_flow.put('flows', l_scheme);
      l_scheme := json_object_t();
      l_scheme.put('oauth2SecurityScheme', l_flow);
      l_schemes := json_object_t();
      l_schemes.put('oauth2', l_scheme);
      l_card.put('securitySchemes', l_schemes);

      l_empty := json_object_t();
      l_empty.put('list', json_array_t());
      l_req := json_object_t();
      l_req.put('oauth2', l_empty);
      l_scheme := json_object_t();
      l_scheme.put('schemes', l_req);
      l_req_list := json_array_t();
      l_req_list.append(l_scheme);
      l_card.put('securityRequirements', l_req_list);
    else
      null;
    end case;

    -- Modes
    l_in_modes.append('text/plain');
    l_in_modes.append('application/json');
    if p_endpoint.accept_files = 'Y' then
      l_in_modes.append('application/pdf');
      l_in_modes.append('image/png');
      l_in_modes.append('image/jpeg');
      l_in_modes.append('image/webp');
      l_in_modes.append('image/gif');
    end if;
    l_card.put('defaultInputModes', l_in_modes);

    if l_agent.output_schema is not null then
      l_out_modes.append('application/json');
    end if;
    l_out_modes.append('text/plain');
    l_card.put('defaultOutputModes', l_out_modes);

    -- The one skill of the agent
    l_skill.put('id', p_endpoint.agent_code);
    l_skill.put('name', p_endpoint.name);
    if p_extended then
      if l_agent.input_schema is not null then
        l_description := l_description || chr(10) || chr(10) || 'Input schema (JSON Schema): '
                      || l_agent.input_schema;
      end if;
      if l_agent.output_schema is not null then
        l_description := l_description || chr(10) || chr(10) || 'Output schema (JSON Schema): '
                      || l_agent.output_schema;
      end if;
    end if;
    l_skill.put('description', l_description);

    l_el := l_extras.get('tags');
    if l_el is not null and l_el.is_array then
      l_tags := json_array_t.parse(l_el.to_clob);
    else
      l_tags := json_array_t();
      l_tags.append(l_agent.agent_type);
    end if;
    l_skill.put('tags', l_tags);

    l_el := l_extras.get('examples');
    if l_el is not null and l_el.is_array then
      l_skill.put('examples', json_array_t.parse(l_el.to_clob));
    end if;

    l_skills.append(l_skill);
    l_card.put('skills', l_skills);

    add_signature(p_endpoint, l_card);

    return l_card;
  exception
    when others then
      uc_ai_logger.log_error(
        'Error building the agent card',
        l_scope,
        sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
      );
      raise;
  end build_agent_card;


  function get_extended_agent_card(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    p_base_url in varchar2
  ) return json_object_t
  as
  begin
    if p_endpoint.auth_mode = 'none' then
      raise_error(
        c_err_no_extended_card
      , 'This agent has no extended agent card: it does not authenticate callers.'
      );
    end if;

    return build_agent_card(p_endpoint, p_base_url, p_extended => true);
  end get_extended_agent_card;


  -- ==========================================================================
  -- SendMessage
  -- ==========================================================================

  -- Makes sure that the request holds a usable message
  procedure validate_message(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    p_message  in json_object_t
  )
  as
    l_parts json_array_t;
    l_part  json_object_t;
    l_kinds pls_integer;
  begin
    if p_message is null then
      raise_error(c_err_invalid_params, 'message is required.');
    end if;
    if nvl(p_message.get_string('role'), '-') <> 'ROLE_USER' then
      raise_error(c_err_invalid_params, 'message.role must be ROLE_USER.');
    end if;
    if get_str(p_message, 'messageId') is null then
      raise_error(c_err_invalid_params, 'message.messageId is required.');
    end if;
    if length(p_message.get_string('messageId')) > 255 then
      raise_error(c_err_invalid_params, 'message.messageId is too long.');
    end if;

    l_parts := p_message.get_array('parts');
    if l_parts is null or l_parts.get_size = 0 then
      raise_error(c_err_invalid_params, 'message.parts needs at least one part.');
    end if;

    <<validate_parts_loop>>
    for i in 0 .. l_parts.get_size - 1 loop
      if not l_parts.get(i).is_object then
        raise_error(c_err_invalid_params, 'Every part must be an object.');
      end if;
      l_part  := treat(l_parts.get(i) as json_object_t);
      l_kinds := case when l_part.has('text') then 1 else 0 end
               + case when l_part.has('raw')  then 1 else 0 end
               + case when l_part.has('url')  then 1 else 0 end
               + case when l_part.has('data') then 1 else 0 end;
      if l_kinds <> 1 then
        raise_error(c_err_invalid_params, 'Every part needs exactly one of text, raw, url or data.');
      end if;

      if l_part.has('url') then
        raise_error(
          c_err_content_type
        , 'Parts of type url are not supported. Send the bytes as a raw part.'
        );
      elsif l_part.has('raw') then
        if p_endpoint.accept_files = 'N' then
          raise_error(c_err_content_type, 'This agent does not accept files.');
        elsif get_str(l_part, 'raw') is null then
          raise_error(c_err_invalid_params, 'A raw part must hold base64 text.');
        end if;
      elsif l_part.has('text') and not l_part.get('text').is_string then
        raise_error(c_err_invalid_params, 'A text part must hold a string.');
      end if;
    end loop validate_parts_loop;
  end validate_message;


  -- The task of an earlier request with the same messageId, or null
  function find_duplicate(
    p_endpoint   in uc_ai_a2a_endpoints%rowtype,
    p_client_id  in varchar2,
    p_message_id in varchar2
  ) return varchar2
  as
    l_task_id uc_ai_a2a_tasks.task_id%type;
  begin
    select task_id
      into l_task_id
      from uc_ai_a2a_tasks
     where endpoint_id = p_endpoint.id
       and client_id   = p_client_id
       and message_id  = p_message_id;

    return l_task_id;
  exception
    when no_data_found then
      return null;
  end find_duplicate;


  /*
   * The context a message belongs to.
   *
   * A message with a taskId continues that task, which this server does not
   * allow: a task that exists is final or running, and the client starts a new
   * task in the same context. A contextId must be the context of an earlier
   * task of this client, or a new one that nobody else uses.
   *
   * po_first_turn is true when the context has no conversation yet.
   */
  procedure resolve_context(
    p_endpoint      in  uc_ai_a2a_endpoints%rowtype,
    p_client_id     in  varchar2,
    p_message       in  json_object_t,
    po_context_id   out varchar2,
    po_first_turn   out boolean
  )
  as
    l_task_id    varchar2(4000 char);
    l_context_id varchar2(4000 char);
    l_task       uc_ai_a2a_tasks%rowtype;
    l_owned      pls_integer;
    l_known      pls_integer;
    l_session    pls_integer;
  begin
    l_task_id    := get_str(p_message, 'taskId');
    l_context_id := get_str(p_message, 'contextId');

    if l_task_id is not null then
      l_task := get_owned_task(p_endpoint, p_client_id, l_task_id);
      if l_context_id is not null and l_context_id <> l_task.context_id then
        raise_error(c_err_invalid_params, 'message.contextId does not belong to message.taskId.');
      end if;
      raise_error(
        c_err_unsupported_op
      , 'A task cannot take another message. Start a new task in the same context: send the message with the contextId of this task and no taskId.'
      );
    end if;

    if l_context_id is null then
      po_context_id := new_uuid();
      po_first_turn := true;
      return;
    end if;

    select case when exists (
             select 1
               from uc_ai_a2a_tasks
              where context_id  = l_context_id
                and endpoint_id = p_endpoint.id
                and client_id   = p_client_id
           ) then 1 else 0 end,
           case when exists (
             select 1
               from uc_ai_agent_sessions
              where session_id = l_context_id
           ) then 1 else 0 end,
           case when exists (
             select 1
               from uc_ai_a2a_tasks
              where context_id = l_context_id
           ) then 1 else 0 end
      into l_owned, l_session, l_known
      from dual;

    if l_owned = 0 then
      -- The same text for a context of someone else and for a malformed one:
      -- the answer must not tell whether the context exists
      if l_known = 1 or l_session = 1
         or not regexp_like(l_context_id, '^[A-Za-z0-9._:-]{1,128}$') then
        raise_error(c_err_invalid_params, 'contextId is not available.');
      end if;
    end if;

    po_context_id := l_context_id;
    po_first_turn := l_session = 0;
  end resolve_context;


  -- The input parameters of the agent as far as the schema names them
  function describe_input(
    p_agent in uc_ai_agents%rowtype
  ) return varchar2
  as
    l_schema json_object_t;
    l_props  json_object_t;
    l_keys   json_key_list;
    l_text   varchar2(4000 char);
  begin
    if p_agent.input_schema is null then
      return 'The agent defines no input schema.';
    end if;

    l_schema := json_object_t.parse(p_agent.input_schema);
    l_props  := l_schema.get_object('properties');
    if l_props is null then
      return 'The agent defines no input properties.';
    end if;

    l_keys := l_props.get_keys;
    <<input_props_loop>>
    for i in 1 .. l_keys.count loop
      l_text := l_text || case when i > 1 then ', ' end || l_keys(i);
    end loop input_props_loop;

    return 'Input properties: ' || l_text || '.';
  exception
    -- @dblinter ignore(G-5040): a schema that is not readable only costs the hint of the error message
    when others then
      -- A schema that is not readable only costs the hint
      return 'The agent defines an input schema.';
  end describe_input;


  -- A required property of the input schema that the input does not hold
  function first_missing_input(
    p_agent in uc_ai_agents%rowtype,
    p_input in json_object_t
  ) return varchar2
  as
    l_schema   json_object_t;
    l_required json_array_t;
  begin
    if p_agent.input_schema is null then
      return null;
    end if;

    l_schema   := json_object_t.parse(p_agent.input_schema);
    l_required := l_schema.get_array('required');
    if l_required is null then
      return null;
    end if;

    <<required_loop>>
    for i in 0 .. l_required.get_size - 1 loop
      if not p_input.has(l_required.get_string(i)) then
        return l_required.get_string(i);
      end if;
    end loop required_loop;

    return null;
  exception
    -- @dblinter ignore(G-5040): a schema that is not readable cannot refuse a request
    when others then
      -- A schema that is not readable cannot refuse a request
      return null;
  end first_missing_input;


  -- Adds a text block to a text, with a blank line between the blocks
  procedure append_text(
    pio_text in out nocopy clob,
    p_block  in            clob
  )
  as
  begin
    if pio_text is null then
      pio_text := p_block;
    else
      pio_text := pio_text || chr(10) || chr(10) || p_block;
    end if;
  end append_text;


  /*
   * Turns the parts of a message into the input of the agent.
   *
   * First turn, or an agent without follow-up support: data parts that hold an
   * object become input parameters, text parts fill text_input_param of the
   * endpoint. Later turn of a profile, orchestrator or handoff agent: the text
   * (and the data, as JSON) is the follow-up message. Raw parts are files.
   */
  function map_input(
    p_endpoint in uc_ai_a2a_endpoints%rowtype,
    p_agent    in uc_ai_agents%rowtype,
    p_message  in json_object_t,
    p_follow_up in boolean
  ) return t_run
  as
    l_run     t_run;
    l_parts   json_array_t;
    l_part    json_object_t;
    l_el      json_element_t;
    l_obj     json_object_t;
    l_keys    json_key_list;
    l_text    clob;
    l_missing varchar2(4000 char);
    l_b64     clob;
  begin
    l_run.input := json_object_t();
    l_run.files := uc_ai_message_api.t_files();
    l_parts     := p_message.get_array('parts');

    <<map_parts_loop>>
    for i in 0 .. l_parts.get_size - 1 loop
      l_part := treat(l_parts.get(i) as json_object_t);

      if l_part.has('text') then
        append_text(l_text, l_part.get_clob('text'));

      elsif l_part.has('data') then
        l_el := l_part.get('data');
        if l_el.is_object and not p_follow_up then
          l_obj  := treat(l_el as json_object_t);
          l_keys := l_obj.get_keys;
          <<map_keys_loop>>
          for k in 1 .. l_keys.count loop
            l_run.input.put(l_keys(k), l_obj.get(l_keys(k)));
          end loop map_keys_loop;
        else
          append_text(l_text, l_el.to_clob);
        end if;

      elsif l_part.has('raw') then
        l_b64 := l_part.get_clob('raw');
        l_run.files.extend;
        l_run.files(l_run.files.count).data_blob  := apex_web_service.clobbase642blob(l_b64);
        l_run.files(l_run.files.count).media_type := coalesce(get_str(l_part, 'mediaType'), 'application/octet-stream');
        l_run.files(l_run.files.count).filename   := substr(get_str(l_part, 'filename'), 1, 4000);
      end if;
    end loop map_parts_loop;

    if p_follow_up then
      if l_text is null and l_run.files.count = 0 then
        raise_error(c_err_invalid_params, 'A follow-up message needs a text part.');
      end if;
      l_run.follow_up := l_text;
      l_run.input     := null;
      return l_run;
    end if;

    if l_text is not null then
      if p_endpoint.text_input_param is null then
        raise_error(
          c_err_invalid_params
        , 'This agent does not take text input. Send the input as a data part. ' || describe_input(p_agent)
        );
      end if;
      -- A data part that already set the parameter wins over the text
      if not l_run.input.has(p_endpoint.text_input_param) then
        l_run.input.put(p_endpoint.text_input_param, l_text);
      end if;
    end if;

    l_missing := first_missing_input(p_agent, l_run.input);
    if l_missing is not null then
      raise_error(
        c_err_invalid_params
      , 'The input "' || l_missing || '" is missing. ' || describe_input(p_agent)
      );
    end if;

    return l_run;
  end map_input;


  -- True when the client does not take JSON but takes plain text
  function wants_text_only(
    p_request in json_object_t
  ) return boolean
  as
    l_config json_object_t;
    l_modes  json_array_t;
    l_json   boolean := false;
    l_text   boolean := false;
  begin
    l_config := p_request.get_object('configuration');
    if l_config is null then
      return false;
    end if;
    l_modes := l_config.get_array('acceptedOutputModes');
    if l_modes is null or l_modes.get_size = 0 then
      return false;
    end if;

    <<modes_loop>>
    for i in 0 .. l_modes.get_size - 1 loop
      if l_modes.get_string(i) in ('application/json', '*/*', 'application/*') then
        l_json := true;
      elsif l_modes.get_string(i) in ('text/plain', 'text/*') then
        l_text := true;
      end if;
    end loop modes_loop;

    return l_text and not l_json;
  end wants_text_only;


  /*
   * The artifact of a finished run: the final message of the agent. A JSON
   * object or array (or a JSON text of an agent with an output schema) is a data
   * part, anything else a text part.
   */
  function build_artifact(
    p_task_id in varchar2,
    p_agent   in uc_ai_agents%rowtype,
    p_result  in json_object_t,
    p_request in json_object_t
  ) return json_object_t
  as
    l_artifact json_object_t := json_object_t();
    l_parts    json_array_t  := json_array_t();
    l_part     json_object_t := json_object_t();
    l_el       json_element_t;
    l_data     json_element_t;
    l_text     clob;
  begin
    l_el := p_result.get('final_message');

    if l_el is not null and (l_el.is_object or l_el.is_array) then
      l_data := l_el;
    elsif l_el is not null and l_el.is_string then
      l_text := p_result.get_clob('final_message');
      if p_agent.output_schema is not null then
        begin
          l_data := json_element_t.parse(l_text);
          if not (l_data.is_object or l_data.is_array) then
            l_data := null;
          end if;
        exception
          -- @dblinter ignore(G-5040): a final message that does not parse is plain text
          when others then
            l_data := null;
        end;
      end if;
    elsif l_el is not null and not l_el.is_null then
      l_text := l_el.to_string;
    end if;

    if l_data is not null and wants_text_only(p_request) then
      l_text := l_data.to_clob;
      l_data := null;
    end if;

    if l_data is not null then
      l_part.put('data', l_data);
      l_part.put('mediaType', 'application/json');
    elsif l_text is not null then
      l_part := text_part(l_text);
    else
      -- An empty answer: Oracle has no empty string, so write the part as text
      l_part := json_object_t('{"text":"","mediaType":"text/plain"}');
    end if;
    l_parts.append(l_part);

    l_artifact.put('artifactId', p_task_id || '-result');
    l_artifact.put('name', 'result');
    l_artifact.put('parts', l_parts);
    return l_artifact;
  end build_artifact;


  /*
   * The request message as it is stored: raw bytes are replaced by a note, and
   * the message carries the IDs of its task and context.
   */
  function stored_message(
    p_message    in json_object_t,
    p_task_id    in varchar2,
    p_context_id in varchar2
  ) return clob
  as
    l_msg   json_object_t;
    l_parts json_array_t;
    l_part  json_object_t;
  begin
    l_msg   := json_object_t.parse(p_message.to_clob);
    l_parts := l_msg.get_array('parts');

    <<stored_parts_loop>>
    for i in 0 .. l_parts.get_size - 1 loop
      l_part := treat(l_parts.get(i) as json_object_t);
      if l_part.has('raw') then
        l_part.remove('raw');
        l_part.put(
          'text'
        , '[file ' || coalesce(get_str(l_part, 'filename'), 'unnamed') || ' ('
          || coalesce(get_str(l_part, 'mediaType'), 'application/octet-stream') || ') omitted]'
        );
      end if;
    end loop stored_parts_loop;

    l_msg.put('taskId', p_task_id);
    l_msg.put('contextId', p_context_id);
    return l_msg.to_clob;
  end stored_message;


  /*
   * Runs the agent for a task that is in the state WORKING, and finishes the
   * task. Never raises: a failed run is a task in the state FAILED.
   */
  procedure run_agent_task(
    p_endpoint   in uc_ai_a2a_endpoints%rowtype,
    p_task_id    in varchar2,
    p_context_id in varchar2,
    p_client_id  in varchar2,
    p_request    in json_object_t,
    p_run        in t_run
  )
  as
    l_scope     uc_ai_logger.scope := gc_scope_prefix || 'run_agent_task';
    l_agent     uc_ai_agents%rowtype;
    l_context   json_object_t := json_object_t();
    l_result    json_object_t;
    l_artifact  json_object_t;
    l_before    number;
    l_exec_id   number;
    l_exec_after number;
  begin
    select nvl(max(id), 0)
      into l_before
      from uc_ai_agent_executions
     where session_id = p_context_id
       and parent_execution_id is null;

    begin
      l_agent := uc_ai_agents_api.get_agent(p_endpoint.agent_code, p_endpoint.agent_version);

      l_context.put('a2a_client', p_client_id);
      l_context.put('a2a_endpoint', p_endpoint.code);

      l_result := uc_ai_agents_api.execute_agent(
        p_agent_code        => p_endpoint.agent_code
      , p_agent_version     => p_endpoint.agent_version
      , p_input_parameters  => p_run.input
      , p_follow_up_message => p_run.follow_up
      , p_session_id        => p_context_id
      , p_files             => p_run.files
      , p_run_context       => l_context
      );

      l_exec_id := l_result.get_number('execution_id');
      if nvl(l_result.get_string('status'), 'completed') <> 'completed' then
        raise_error(
          c_err_invalid_agent_resp
        , 'The agent run ended with the status ' || l_result.get_string('status') || '.'
        );
      end if;

      l_artifact := build_artifact(p_task_id, l_agent, l_result, p_request);
      finish_task(
        p_task_id      => p_task_id
      , p_state        => c_state_completed
      , p_result       => l_artifact.to_clob
      , p_execution_id => l_exec_id
      );
    exception
      -- @dblinter ignore(G-5040): a failed run is a state of the task; the error is logged here and must not reach the client
      when others then
        uc_ai_logger.log_error(
          'A2A task ' || p_task_id || ' failed',
          l_scope,
          sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );

        -- The run did not return its ID: find it as the newest turn of the session
        select max(id)
          into l_exec_after
          from uc_ai_agent_executions
         where session_id = p_context_id
           and parent_execution_id is null
           and id > l_before;

        finish_task(
          p_task_id        => p_task_id
        , p_state          => c_state_failed
        , p_status_message => c_failed_text
        , p_execution_id   => l_exec_after
        );
    end;
  end run_agent_task;


  /*
   * The input of the run for a message: whether the message continues a
   * conversation decides how map_input reads it.
   */
  function build_run(
    p_endpoint   in uc_ai_a2a_endpoints%rowtype,
    p_message    in json_object_t,
    p_first_turn in boolean
  ) return t_run
  as
    l_agent     uc_ai_agents%rowtype;
    l_follow_up boolean;
  begin
    l_agent     := uc_ai_agents_api.get_agent(p_endpoint.agent_code, p_endpoint.agent_version);
    l_follow_up := not p_first_turn
                   and l_agent.agent_type in (
                         uc_ai_agents_api.c_type_profile
                       , uc_ai_agents_api.c_type_orchestrator
                       , uc_ai_agents_api.c_type_handoff);

    return map_input(p_endpoint, l_agent, p_message, l_follow_up);
  end build_run;


  /*
   * Creates the scheduler job that runs a task in the background.
   * create_job commits, so this runs in an autonomous transaction: the commit
   * must not end the transaction of the caller. The task row is committed
   * already (insert_task), so the job finds it.
   */
  procedure start_job(
    p_task_id  in varchar2,
    p_job_name in varchar2
  )
  as
    -- @dblinter ignore(G-3330): dbms_scheduler.create_job commits; that must not end the transaction of the caller
    pragma autonomous_transaction;
  begin
    sys.dbms_scheduler.create_job(
      job_name   => p_job_name
    , job_type   => 'PLSQL_BLOCK'
    , job_action => 'begin uc_ai_a2a.run_task(''' || p_task_id || '''); end;'
    , start_date => systimestamp
    , enabled    => true
    , auto_drop  => true
    , comments   => 'UC AI A2A task'
    );
    commit;
  end start_job;


  /*
   * Checks a SendMessageRequest and records the task.
   *   Blocking (p_async false): runs the agent, returns the task as it ends up.
   *   Background (p_async true): the task is SUBMITTED, a one-off scheduler job
   *     runs it (uc_ai_a2a.run_task), the call returns the SUBMITTED task.
   * A repeated messageId returns the task of the first request without a new run.
   * The task row, the push configuration and the job are committed on their own
   * (autonomous), so the job sees them and the caller's transaction stays open.
   */
  function process_message(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_request   in json_object_t,
    p_async     in boolean default false
  ) return uc_ai_a2a_tasks%rowtype
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'process_message';
    l_message    json_object_t;
    l_config     json_object_t;
    l_push       json_object_t;
    l_dup_id     uc_ai_a2a_tasks.task_id%type;
    l_context_id uc_ai_a2a_tasks.context_id%type;
    l_first_turn boolean;
    l_run        t_run;
    l_row        uc_ai_a2a_tasks%rowtype;
    l_now        timestamp;
  begin
    l_now     := utc_now();
    l_message := p_request.get_object('message');
    validate_message(p_endpoint, l_message);

    l_config := p_request.get_object('configuration');
    if l_config is not null then
      l_push := l_config.get_object('taskPushNotificationConfig');
    end if;
    if l_push is not null then
      require_push_support(p_endpoint);
      check_push_config(l_push);
    end if;

    -- A client that repeats a request gets the task of the first one
    l_dup_id := find_duplicate(p_endpoint, p_client_id, l_message.get_string('messageId'));
    if l_dup_id is not null then
      return get_owned_task(p_endpoint, p_client_id, l_dup_id);
    end if;

    resolve_context(p_endpoint, p_client_id, l_message, l_context_id, l_first_turn);
    l_run := build_run(p_endpoint, l_message, l_first_turn);

    l_row.task_id         := new_uuid();
    l_row.context_id      := l_context_id;
    l_row.endpoint_id     := p_endpoint.id;
    l_row.client_id       := p_client_id;
    l_row.message_id      := l_message.get_string('messageId');
    l_row.state           := case when p_async then c_state_submitted else c_state_working end;
    l_row.request_message := stored_message(l_message, l_row.task_id, l_context_id);
    l_row.created_at      := l_now;
    l_row.updated_at      := l_now;
    if p_async then
      -- The job needs the whole request, files included, to build its run
      l_row.pending_request := p_request.to_clob;
      l_row.job_name        := 'UC_AI_A2A_' || upper(replace(l_row.task_id, '-'));
    end if;

    begin
      insert_task(l_row);
    exception
      when dup_val_on_index then
        -- A second request with the same messageId won the race
        l_dup_id := find_duplicate(p_endpoint, p_client_id, l_message.get_string('messageId'));
        if l_dup_id is null then
          raise;
        end if;
        return get_owned_task(p_endpoint, p_client_id, l_dup_id);
    end;

    if l_push is not null then
      store_push_row(new_push_row(l_row.task_id, l_push));
    end if;

    if p_async then
      begin
        start_job(l_row.task_id, l_row.job_name);
      exception
        -- @dblinter ignore(G-5040): a job that cannot start (no CREATE JOB privilege) is a failed task, not a failed request
        when others then
          uc_ai_logger.log_error(
            'Could not create the job of A2A task ' || l_row.task_id,
            l_scope,
            sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
          );
          finish_task(l_row.task_id, c_state_failed, 'The agent run could not be started.');
      end;
    else
      run_agent_task(p_endpoint, l_row.task_id, l_context_id, p_client_id, p_request, l_run);
    end if;

    return get_owned_task(p_endpoint, p_client_id, l_row.task_id);
  end process_message;


  function send_message(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_request   in json_object_t
  ) return json_object_t
  as
    l_row      uc_ai_a2a_tasks%rowtype;
    l_config   json_object_t;
    l_async    boolean := false;
    l_response json_object_t := json_object_t();
  begin
    -- returnImmediately runs the task in the background, when the endpoint allows
    -- it. An endpoint with allow_async = N ignores the hint and blocks.
    l_config := p_request.get_object('configuration');
    if l_config is not null then
      l_async := get_bool(l_config, 'returnImmediately', false) and p_endpoint.allow_async = 'Y';
    end if;
    l_row := process_message(p_endpoint, p_client_id, p_request, l_async);

    l_response.put(
      'task'
    , task_json(l_row, case when l_config is not null then get_history_length(l_config) end)
    );
    return l_response;
  end send_message;


  -- ==========================================================================
  -- Streaming
  -- ==========================================================================

  /*
   * The StreamResponse events of a task: the task (as it was at the start), the
   * artifact, the final status. Every event is an object with one key: task,
   * artifactUpdate or statusUpdate.
   */
  function stream_events(
    p_row in uc_ai_a2a_tasks%rowtype
  ) return json_array_t
  as
    l_events   json_array_t := json_array_t();
    l_event    json_object_t;
    l_snapshot uc_ai_a2a_tasks%rowtype;
    l_update   json_object_t;
  begin
    -- The first event shows the task at work, before its result
    l_snapshot                := p_row;
    l_snapshot.state          := c_state_working;
    l_snapshot.status_message := null;
    l_snapshot.result         := null;
    l_snapshot.updated_at     := p_row.created_at;
    l_event := json_object_t();
    l_event.put('task', task_json(l_snapshot));
    l_events.append(l_event);

    if p_row.result is not null then
      l_update := json_object_t();
      l_update.put('taskId', p_row.task_id);
      l_update.put('contextId', p_row.context_id);
      l_update.put('artifact', json_object_t.parse(p_row.result));
      l_update.put('lastChunk', true);
      l_event := json_object_t();
      l_event.put('artifactUpdate', l_update);
      l_events.append(l_event);
    end if;

    l_update := json_object_t();
    l_update.put('taskId', p_row.task_id);
    l_update.put('contextId', p_row.context_id);
    l_update.put('status', status_json(p_row));
    l_event := json_object_t();
    l_event.put('statusUpdate', l_update);
    l_events.append(l_event);

    return l_events;
  end stream_events;


  function send_streaming_message(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_request   in json_object_t
  ) return json_array_t
  as
  begin
    -- A stream follows the task to its end, so returnImmediately has no meaning
    -- here and is ignored: the run is blocking and the events go out together
    return stream_events(process_message(p_endpoint, p_client_id, p_request, false));
  end send_streaming_message;


  -- Waits one second. dbms_session.sleep needs Oracle 18c; dbms_lock.sleep is the
  -- fallback (it needs a grant). Both through dynamic SQL, so the package compiles
  -- on 12.2.
  procedure sleep_one_second
  as
    c_sleep_session constant varchar2(100 char) := 'begin sys.dbms_session.sleep(1); end;';
    c_sleep_lock    constant varchar2(100 char) := 'begin sys.dbms_lock.sleep(1); end;';
  begin
    execute immediate c_sleep_session;
  exception
    -- @dblinter ignore(G-5040): no dbms_session.sleep on this version: the fallback decides
    when others then
      execute immediate c_sleep_lock;
  end sleep_one_second;


  /*
   * What SubscribeToTask sends when the wait ends before the task: the task as
   * it is and its current status.
   */
  function open_events(
    p_row in uc_ai_a2a_tasks%rowtype
  ) return json_array_t
  as
    l_events json_array_t := json_array_t();
    l_event  json_object_t;
    l_update json_object_t;
  begin
    l_event := json_object_t();
    l_event.put('task', task_json(p_row));
    l_events.append(l_event);

    l_update := json_object_t();
    l_update.put('taskId', p_row.task_id);
    l_update.put('contextId', p_row.context_id);
    l_update.put('status', status_json(p_row));
    l_event := json_object_t();
    l_event.put('statusUpdate', l_update);
    l_events.append(l_event);

    return l_events;
  end open_events;


  /*
   * SubscribeToTask: polls the task row once a second, for at most
   * c_subscribe_max_seconds, until the task is final. The events (see
   * stream_events) go out together at the end: ORDS buffers the response.
   */
  function subscribe_to_task(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_array_t
  as
    l_row uc_ai_a2a_tasks%rowtype;
  begin
    l_row := get_owned_task(p_endpoint, p_client_id, get_required_id(p_params));
    if is_terminal(l_row.state) then
      raise_error(c_err_unsupported_op, 'The task is in a final state. It has no updates to subscribe to.');
    end if;

    <<wait_loop>>
    for i in 1 .. c_subscribe_max_seconds loop
      sleep_one_second;
      l_row := get_owned_task(p_endpoint, p_client_id, l_row.task_id);
      exit wait_loop when is_terminal(l_row.state);
    end loop wait_loop;

    if is_terminal(l_row.state) then
      return stream_events(l_row);
    end if;

    return open_events(l_row);
  end subscribe_to_task;


  -- ==========================================================================
  -- GetTask, ListTasks, CancelTask
  -- ==========================================================================

  function get_task(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t
  as
    l_row uc_ai_a2a_tasks%rowtype;
  begin
    l_row := get_owned_task(p_endpoint, p_client_id, get_required_id(p_params));
    return task_json(l_row, get_history_length(p_params));
  end get_task;


  function list_tasks(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t
  as
    l_context    varchar2(255 char);
    l_status     varchar2(30 char);
    l_page_size  number;
    l_token      varchar2(100 char);
    l_tok_ts     timestamp;
    l_tok_id     varchar2(36 char);
    l_after_txt  varchar2(100 char);
    l_after      timestamp;
    l_history    number;
    l_include    boolean;
    l_total      pls_integer;
    l_ids        sys.odcivarchar2list;
    l_row        uc_ai_a2a_tasks%rowtype;
    l_tasks      json_array_t := json_array_t();
    l_next       varchar2(100 char);
    l_response   json_object_t;
    l_count      pls_integer;
  begin
    -- Every key is there from the start: nextPageToken is an empty string, not absent
    l_response := json_object_t('{"tasks":[],"nextPageToken":"","pageSize":0,"totalSize":0}');
    l_context := substr(get_str(p_params, 'contextId'), 1, 255);
    l_status  := substr(get_str(p_params, 'status'), 1, 30);
    if l_status is not null and l_status not in (
         c_state_submitted, c_state_working, c_state_completed, c_state_failed
       , c_state_canceled, c_state_input_required, c_state_rejected, c_state_auth_required) then
      raise_error(c_err_invalid_params, 'status is not a task state.');
    end if;

    l_page_size := nvl(get_num(p_params, 'pageSize'), c_default_page_size);
    if l_page_size < 1 or l_page_size > c_max_page_size or l_page_size <> trunc(l_page_size) then
      raise_error(c_err_invalid_params, 'pageSize must be a whole number from 1 to ' || c_max_page_size || '.');
    end if;

    l_token := substr(get_str(p_params, 'pageToken'), 1, 100);
    if l_token is not null then
      if not regexp_like(l_token, '^[0-9]{20}~[0-9a-f-]{36}$') then
        raise_error(c_err_invalid_params, 'pageToken is not valid.');
      end if;
      l_tok_ts := to_timestamp(substr(l_token, 1, 20), 'YYYYMMDDHH24MISSFF6');
      l_tok_id := substr(l_token, 22);
    end if;

    l_after_txt := substr(get_str(p_params, 'statusTimestampAfter'), 1, 100);
    if l_after_txt is not null then
      begin
        l_after := sys_extract_utc(to_timestamp_tz(l_after_txt, 'YYYY-MM-DD"T"HH24:MI:SS.FFTZR'));
      exception
        -- @dblinter ignore(G-5040): any parse failure is invalid params; the parser text stays out of the response
        when others then
          raise_error(c_err_invalid_params, 'statusTimestampAfter must be an ISO 8601 timestamp.');
      end;
    end if;

    l_history := get_history_length(p_params);
    l_include := get_bool(p_params, 'includeArtifacts', false);

    select count(*)
      into l_total
      from uc_ai_a2a_tasks
     where endpoint_id = p_endpoint.id
       and client_id   = p_client_id
       and (l_context is null or context_id = l_context)
       and (l_status is null or state = l_status)
       and (l_after is null or updated_at >= l_after);

    -- One row more than the page, to know whether another page follows
    select task_id
      bulk collect into l_ids
      from (
        select task_id
          from uc_ai_a2a_tasks
         where endpoint_id = p_endpoint.id
           and client_id   = p_client_id
           and (l_context is null or context_id = l_context)
           and (l_status is null or state = l_status)
           and (l_after is null or updated_at >= l_after)
           and (l_tok_ts is null
                or updated_at < l_tok_ts
                or (updated_at = l_tok_ts and task_id > l_tok_id))
         order by updated_at desc, task_id
      )
     where rownum <= l_page_size + 1;

    l_count := least(l_ids.count, l_page_size);
    <<list_page_loop>>
    for i in 1 .. l_count loop
      select *
        into l_row
        from uc_ai_a2a_tasks
       where task_id = l_ids(i);

      l_tasks.append(task_json(l_row, l_history, l_include));
    end loop list_page_loop;

    if l_ids.count > l_page_size then
      l_next := to_char(l_row.updated_at, 'YYYYMMDDHH24MISSFF6') || '~' || l_row.task_id;
    end if;

    l_response.put('tasks', l_tasks);
    if l_next is not null then
      l_response.put('nextPageToken', l_next);
    end if;
    l_response.put('pageSize', l_page_size);
    l_response.put('totalSize', l_total);
    return l_response;
  end list_tasks;


  -- Autonomous: the failed run must show at once, also when the caller rolls back
  procedure fail_canceled_execution(
    p_context_id in varchar2
  )
  as
    -- @dblinter ignore(G-3330): the canceled run must be recorded whatever the caller's transaction does
    pragma autonomous_transaction;
    l_exec_id number;
  begin
    -- The run is the newest turn of the session. A run that the scheduler stopped
    -- may have recorded the interrupt (ORA-01013) already; the cancel is the reason.
    select max(id)
      into l_exec_id
      from uc_ai_agent_executions
     where session_id = p_context_id
       and parent_execution_id is null;

    update uc_ai_agent_executions
       set status        = uc_ai_agents_api.c_exec_failed,
           error_message = 'Canceled by the A2A client',
           completed_at  = coalesce(completed_at, systimestamp)
     where id = l_exec_id
       and (status in (uc_ai_agents_api.c_exec_pending, uc_ai_agents_api.c_exec_running)
            or error_message like 'ORA-01013%');
    commit;
  exception
    when others then
      rollback;
      raise;
  end fail_canceled_execution;


  /*
   * CancelTask. A final task cannot be canceled. A SUBMITTED task loses its job.
   * A WORKING task is marked CANCELED first (so the late end of the run cannot
   * overwrite it, see set_task_state), then its job is stopped and the execution
   * is marked failed. A job that cannot be stopped is logged; the task stays
   * CANCELED either way.
   */
  function cancel_task(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t
  as
    l_scope uc_ai_logger.scope := gc_scope_prefix || 'cancel_task';
    l_row   uc_ai_a2a_tasks%rowtype;
    l_state varchar2(30 char);
  begin
    l_row := get_owned_task(p_endpoint, p_client_id, get_required_id(p_params));
    if is_terminal(l_row.state) then
      raise_error(c_err_task_not_cancelable, 'The task is in a final state and cannot be canceled.');
    end if;
    l_state := l_row.state;

    if l_state = c_state_submitted and l_row.job_name is not null then
      begin
        sys.dbms_scheduler.drop_job(job_name => l_row.job_name, force => true);
      exception
        -- @dblinter ignore(G-5040): the job may have run or dropped itself; the task state decides
        when others then
          uc_ai_logger.log_warning('Could not drop job ' || l_row.job_name, l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      end;
    end if;

    finish_task(l_row.task_id, c_state_canceled, 'Canceled by the client.');

    if l_state <> c_state_submitted then
      if l_row.job_name is not null then
        begin
          sys.dbms_scheduler.stop_job(job_name => l_row.job_name, force => false);
        exception
          -- @dblinter ignore(G-5040): a job that is gone or cannot be stopped does not undo the cancel
          when others then
            uc_ai_logger.log_warning('Could not stop job ' || l_row.job_name, l_scope, sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
        end;
      end if;
      fail_canceled_execution(l_row.context_id);
    end if;

    return task_json(get_owned_task(p_endpoint, p_client_id, l_row.task_id), get_history_length(p_params));
  end cancel_task;


  -- ==========================================================================
  -- Push notification configurations
  -- ==========================================================================

  -- The task of a request that works on a configuration
  function get_push_task(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return uc_ai_a2a_tasks%rowtype
  as
  begin
    require_push_support(p_endpoint);
    return get_owned_task(p_endpoint, p_client_id, get_required_id(p_params, 'taskId'));
  end get_push_task;


  -- CreateTaskPushNotificationConfig {taskId, id, url, token, authentication}
  function create_push_config(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t
  as
    l_task uc_ai_a2a_tasks%rowtype;
    l_row  uc_ai_a2a_push_configs%rowtype;
  begin
    l_task := get_push_task(p_endpoint, p_client_id, p_params);
    l_row  := new_push_row(l_task.task_id, p_params);
    store_push_row(l_row);

    -- A task that has ended already sends no more events: send its final state
    -- to the new webhook now, or the client would wait for nothing.
    if is_terminal(l_task.state) then
      deliver_push_notifications(l_task.task_id, l_row.id);
    end if;

    return push_config_json(l_row);
  end create_push_config;


  -- GetTaskPushNotificationConfig {taskId, id}
  function get_push_config(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t
  as
    l_task uc_ai_a2a_tasks%rowtype;
    l_cfg  uc_ai_a2a_push_configs%rowtype;
    l_id   varchar2(4000 char);
  begin
    l_task := get_push_task(p_endpoint, p_client_id, p_params);
    l_id   := get_required_id(p_params);

    <<find_loop>>
    for l_found in (
      select id
        from uc_ai_a2a_push_configs
       where task_id   = l_task.task_id
         and config_id = l_id
    ) loop
      select *
        into l_cfg
        from uc_ai_a2a_push_configs
       where id = l_found.id;

      return push_config_json(l_cfg);
    end loop find_loop;

    raise_error(c_err_task_not_found, 'The push notification configuration does not exist.');
    return null;
  end get_push_config;


  -- ListTaskPushNotificationConfigs {taskId, pageSize, pageToken}
  function list_push_configs(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t
  as
    l_task      uc_ai_a2a_tasks%rowtype;
    l_page_size number;
    l_token     varchar2(100 char);
    l_offset    pls_integer := 0;
    l_configs   json_array_t := json_array_t();
    l_count     pls_integer := 0;
    l_cfg       uc_ai_a2a_push_configs%rowtype;
    l_response  json_object_t;
  begin
    l_task := get_push_task(p_endpoint, p_client_id, p_params);

    l_page_size := nvl(get_num(p_params, 'pageSize'), c_default_page_size);
    if l_page_size < 1 or l_page_size > c_max_page_size or l_page_size <> trunc(l_page_size) then
      raise_error(c_err_invalid_params, 'pageSize must be a whole number from 1 to ' || c_max_page_size || '.');
    end if;

    -- The token is the number of configurations already sent
    l_token := substr(get_str(p_params, 'pageToken'), 1, 100);
    if l_token is not null then
      if not regexp_like(l_token, '^[0-9]{1,9}$') then
        raise_error(c_err_invalid_params, 'pageToken is not valid.');
      end if;
      l_offset := to_number(l_token);
    end if;

    l_response := json_object_t('{"configs":[],"nextPageToken":""}');

    <<configs_loop>>
    for l_page in (
      select id
        from (select c.id, row_number() over (order by c.created_at, c.id) as rn
                from uc_ai_a2a_push_configs c
               where c.task_id = l_task.task_id)
       where rn > l_offset
         and rn <= l_offset + l_page_size + 1
       order by rn
    ) loop
      l_count := l_count + 1;
      if l_count > l_page_size then
        l_response.put('nextPageToken', to_char(l_offset + l_page_size));
      else
        select *
          into l_cfg
          from uc_ai_a2a_push_configs
         where id = l_page.id;

        l_configs.append(push_config_json(l_cfg));
      end if;
    end loop configs_loop;

    l_response.put('configs', l_configs);
    return l_response;
  end list_push_configs;


  -- DeleteTaskPushNotificationConfig {taskId, id}. Idempotent: a configuration
  -- that is not there is no error. The answer is an empty object.
  function delete_push_config(
    p_endpoint  in uc_ai_a2a_endpoints%rowtype,
    p_client_id in varchar2,
    p_params    in json_object_t
  ) return json_object_t
  as
    l_task uc_ai_a2a_tasks%rowtype;
  begin
    l_task := get_push_task(p_endpoint, p_client_id, p_params);
    delete_push_config_row(l_task.task_id, get_required_id(p_params));
    return json_object_t();
  end delete_push_config;


  -- ==========================================================================
  -- Background runs
  -- ==========================================================================

  /*
   * Runs a task that was accepted with returnImmediately. SUBMITTED -> WORKING,
   * then the same code as a blocking call, then the final state and the push
   * notifications. A task that is not SUBMITTED (canceled) is left alone.
   */
  procedure run_task(
    p_task_id in varchar2
  )
  as
    l_scope      uc_ai_logger.scope := gc_scope_prefix || 'run_task';
    l_row        uc_ai_a2a_tasks%rowtype;
    l_endpoint   uc_ai_a2a_endpoints%rowtype;
    l_request    json_object_t;
    l_message    json_object_t;
    l_session    pls_integer;
    l_run        t_run;
  begin
    select *
      into l_row
      from uc_ai_a2a_tasks
     where task_id = p_task_id;

    if l_row.state <> c_state_submitted or l_row.pending_request is null then
      return;
    end if;

    -- Takes the task or finds that a cancel was faster
    if not claim_task(p_task_id) then
      return;
    end if;

    begin
      select *
        into l_endpoint
        from uc_ai_a2a_endpoints
       where id = l_row.endpoint_id;

      l_request := json_object_t.parse(l_row.pending_request);
      l_message := l_request.get_object('message');

      -- Earlier turns of the context decide how the message is read
      select case when exists (
               select 1
                 from uc_ai_agent_sessions
                where session_id = l_row.context_id
             ) then 1 else 0 end
        into l_session
        from dual;

      l_run := build_run(l_endpoint, l_message, l_session = 0);
      run_agent_task(l_endpoint, p_task_id, l_row.context_id, l_row.client_id, l_request, l_run);
    exception
      -- @dblinter ignore(G-5040): a task that cannot start is a failed task; the error is logged here and must not reach the scheduler
      when others then
        uc_ai_logger.log_error(
          'A2A task ' || p_task_id || ' could not run',
          l_scope,
          sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace
        );
        finish_task(p_task_id, c_state_failed, c_failed_text);
    end;
  exception
    when no_data_found then
      uc_ai_logger.log_warning('A2A task ' || p_task_id || ' does not exist', l_scope, sys.dbms_utility.format_error_backtrace);
  end run_task;

end uc_ai_a2a_core;
/
