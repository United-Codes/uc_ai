create or replace package test_uc_ai_a2a as
  -- @dblinter ignore(g-5010): allow logger in test packages

  --%suite(A2A server)
  --%suitepath(uc_ai.a2a)
  --%rollback(manual)

  --%beforeall
  procedure setup;

  --%afterall
  procedure teardown;

  --%aftereach
  procedure reset_transport;

  -- Endpoint management

  --%test(expose_agent creates an endpoint and replaces the configuration of the same code)
  procedure expose_creates_and_upserts;

  --%test(expose_agent rejects an endpoint code that is not a lowercase slug)
  procedure expose_rejects_invalid_code;

  --%test(expose_agent rejects an unknown auth mode)
  procedure expose_rejects_unknown_auth_mode;

  --%test(expose_agent rejects an agent that does not exist)
  procedure expose_rejects_unknown_agent;

  --%test(text_input_param is derived from an input schema with one required string)
  procedure expose_derives_text_input_param;

  --%test(No text_input_param is derived from an input schema with two required inputs)
  procedure expose_no_text_param_for_two_inputs;

  --%test(An oauth2 endpoint needs the client ID of the front end)
  procedure oauth2_requires_client_id;

  --%test(A disabled endpoint answers 404 on every route)
  procedure disabled_endpoint_answers_404;

  --%test(remove_endpoint deletes keys, tasks and push configurations)
  procedure remove_endpoint_deletes_children;


  --%test(create_api_key stores the hash of the key, not the key)
  procedure api_key_stores_hash_only;

  --%test(A missing or unknown API key answers 401)
  procedure api_key_missing_or_wrong_is_401;

  --%test(A revoked API key answers 401)
  procedure api_key_revoked_is_401;

  --%test(An expired API key answers 401)
  procedure api_key_expired_is_401;

  --%test(A second key for the same client is rejected until the first is revoked)
  procedure api_key_duplicate_client_rejected;

  -- Agent card

  --%test(The agent card has the required fields)
  procedure card_required_fields;

  --%test(The card builds two absolute interface URLs from the request URL)
  procedure card_interfaces_from_request_url;

  --%test(The card builds the interface URLs from base_url when set)
  procedure card_interfaces_from_base_url;

  --%test(The card announces the security scheme of the auth mode)
  procedure card_security_schemes_per_auth_mode;

  --%test(The card route needs no authentication)
  procedure card_needs_no_auth;

  --%test(extendedAgentCard capability follows the auth mode)
  procedure card_extended_capability;

  --%test(The output modes follow the output schema of the agent)
  procedure card_output_modes;

  --%test(card_extras are merged into the card)
  procedure card_extras_merge;

  -- JSON-RPC

  --%test(SendMessage with text completes with the artifact text)
  procedure rpc_send_text_completed;

  --%test(SendMessage with a data part fills the input and returns a data artifact)
  procedure rpc_send_data_part;

  --%test(SendMessage without a required input is -32602)
  procedure rpc_missing_required_input;

  --%test(A url part is -32005)
  procedure rpc_url_part_unsupported;

  --%test(A message without parts, with a bad role or without messageId is -32602)
  procedure rpc_invalid_message;

  --%test(Parse error, invalid request and unknown method map to their JSON-RPC codes)
  procedure rpc_protocol_errors;

  --%test(Legacy method names and an old A2A-Version are -32009)
  procedure rpc_legacy_and_version;

  --%test(GetTask honours historyLength)
  procedure rpc_get_task_history_length;

  --%test(ListTasks pages with pageSize, nextPageToken and totalSize)
  procedure rpc_list_tasks_paging;

  --%test(ListTasks filters by contextId)
  procedure rpc_list_tasks_context_filter;

  --%test(CancelTask on a completed task is -32002)
  procedure rpc_cancel_completed_task;

  --%test(A repeated messageId returns the same task)
  procedure rpc_duplicate_message_id;

  --%test(A follow-up in the same context is a new task)
  procedure rpc_follow_up_same_context;

  --%test(A context of another client is -32602)
  procedure rpc_foreign_context_rejected;

  --%test(A task of another client is -32001)
  procedure rpc_task_of_other_client;

  --%test(A message that names a task is -32004)
  procedure rpc_task_id_in_message_unsupported;

  --%test(GetExtendedAgentCard needs authentication and extends the skill)
  procedure rpc_extended_card;

  -- REST

  --%test(message:send returns the task)
  procedure rest_message_send;

  --%test(GET tasks/{id} returns the task)
  procedure rest_get_task;

  --%test(GET tasks filters and pages by query string)
  procedure rest_list_tasks;

  --%test(tasks/{id}:cancel on a completed task is 400 TASK_NOT_CANCELABLE)
  procedure rest_cancel_completed_task;

  --%test(An unknown task is 404 with the ErrorInfo error body)
  procedure rest_unknown_task_and_error_shape;

  --%test(GET extendedAgentCard returns the extended card)
  procedure rest_extended_card;

  -- Streaming

  --%test(SendStreamingMessage answers with JSON-RPC wrapped events)
  procedure stream_jsonrpc_events;

  --%test(message:stream answers with bare events)
  procedure stream_rest_events;

  -- Failure

  --%test(A failing agent run is FAILED without internals)
  procedure failure_hides_internals;

  --%test(A failed run rolls back what its steps wrote; the task is FAILED and the row is gone)
  procedure failed_run_rolls_back_writes;

  --%test(A completed run has committed what its steps wrote when the task shows COMPLETED)
  procedure completed_run_commits_writes;

  -- Push notifications

  --%test(Push configurations can be created, read, listed and deleted)
  procedure push_config_crud;

  --%test(A push configuration with a bad URL is -32602)
  procedure push_config_rejects_bad_url;

  --%test(Push configurations are refused when allow_async is N)
  procedure push_not_supported_without_async;

  --%test(A completed task is POSTed to the push URL)
  procedure push_delivery_on_completion;

  --%test(A failed push delivery does not fail the task)
  procedure push_delivery_failure_is_recorded;

  --%test(REST push configuration paths work)
  procedure push_rest_config_crud;

  -- Async runs

  --%test(returnImmediately returns SUBMITTED, run_task completes the task)
  procedure async_submitted_then_run;

  --%test(Canceling a SUBMITTED task drops the job and run_task leaves it CANCELED)
  procedure async_cancel_submitted;

  --%test(returnImmediately is ignored when allow_async is N)
  procedure async_ignored_without_allow_async;

  -- Card signing

  --%test(A signing key adds a JWS signature to the card)
  procedure signing_adds_signature;

  --%test(A key that cannot sign is refused)
  procedure signing_rejects_bad_key;

  --%test(A null key stops signing)
  procedure signing_can_be_cleared;

end test_uc_ai_a2a;
/
