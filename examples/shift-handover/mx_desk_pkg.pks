create or replace package mx_desk_pkg
as
  /**
  * UC AI tutorial — "Give an Agent a Memory"
  *
  * The two read tools of the maintenance desk.
  *
  * Both handlers follow the same two rules:
  *
  *   1. The asset comes from the RUN CONTEXT, never from the model. Neither
  *      tool has an argument, so there is nothing for a conversation to point
  *      at a different machine.
  *   2. A handler reads. Nothing in this package writes.
  *
  * The run context is bound by the caller in p_run_context and UC AI adds it to
  * the arguments of every tool call under the key uc_ai.c_run_context_key.
  */

  -- Reads one key out of the run context UC AI added to the arguments.
  -- Returns null when the run carries no context, or the key is absent.
  function context_value(
    p_arguments in clob
  , p_key       in varchar2
  ) return varchar2;

  -- The asset in front of the technician, with its open alarms.
  function get_asset(p_arguments in clob) return clob;

  -- The work-order history of that asset, newest first.
  function list_work_orders(p_arguments in clob) return clob;

end mx_desk_pkg;
/
