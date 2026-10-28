create or replace package uc_ai_chat_widgets
  authid definer
as

  -- ============================================================================
  -- UC AI Chat widgets
  --
  -- A region that enables widgets (region attribute "widgets") lets the model put
  -- a small widget into its answer as a fenced block:
  --
  --   ```ucai-widget
  --   {"type":"stat_card","label":"Open invoices","value":42}
  --   ```
  --
  -- The plug-in never trusts that JSON. render() cuts the answer into parts and
  -- rebuilds every widget spec from a whitelist of keys, so the browser only ever
  -- gets known keys, bounded sizes, and plain scalars. A widget that fails
  -- validation is NOT an error: it stays in the answer as text, with the reason
  -- in the 'rejected' member of that part.
  --
  -- Table and chart data comes from "data" (inline rows) or from "source":
  -- "tool:<tool_name>", which names a tool that ran in THIS turn. The server
  -- resolves the source, so the model does not retype the rows. When the same
  -- tool ran more than once, the optional "args" object picks the call: the
  -- latest call whose arguments contain every key and value of "args". Without
  -- "args" the latest call of that tool wins.
  --
  -- Which types are enabled is decided server-side from the region attribute
  -- (see normalize_types), never by the client.
  --
  -- CUSTOM WIDGET TYPES
  -- You can add model-facing types of your own (register_type). The model
  -- writes a small spec that names things by id, for example
  --   {"type":"file_list","ids":["4711"]}
  -- and the provider package of that type turns it into a spec of a RENDER type
  -- that the browser already knows. Today the render type is "item_list". The
  -- provider never touches the browser: the plug-in passes whatever it returns
  -- through its own whitelist (clean_item_list) like any built-in widget.
  --
  -- The provider is a package in the same schema with exactly these two members:
  --
  --   function get_protocol(p_type in varchar2) return clob;
  --     The line(s) for the WIDGET PROTOCOL block: how the model writes this type.
  --
  --   procedure build_spec(
  --     p_type       in  varchar2,
  --     p_spec       in  clob,           -- the JSON the model wrote
  --     p_tool_calls in  clob,           -- JSON array of this turn's tool calls:
  --                                      --   [{"name","args","output"}, ...]
  --     po_spec      out nocopy clob,    -- JSON object of the render type
  --     po_reason    out nocopy varchar2 -- not null = reject, shown as text
  --   );
  --
  -- The provider runs with the rights and the session context of the turn, so it
  -- can (and must) check that the current user may see what the model names, and
  -- that the model got it from a tool in this turn. An error raised by the provider
  -- never fails the answer: the widget shows as text.
  --
  -- uc_ai_chat.execute_agent_job renders once after the run and stores the
  -- result on the assistant row (uc_ai_chat_messages.parts); AI_FETCH_MESSAGES
  -- only emits that snapshot.
  -- ============================================================================

  c_fence constant varchar2(20 char) := 'ucai-widget';

  c_type_stat_card constant varchar2(20 char) := 'stat_card';
  c_type_status    constant varchar2(20 char) := 'status';
  c_type_key_value constant varchar2(20 char) := 'key_value';
  c_type_table     constant varchar2(20 char) := 'table';
  c_type_chart     constant varchar2(20 char) := 'chart';

  -- Render-only: the model cannot ask for it, only a provider type can produce it.
  c_type_item_list constant varchar2(20 char) := 'item_list';

  c_all_types constant varchar2(100 char) := 'stat_card:status:key_value:table:chart';

  c_max_widgets constant pls_integer := 6;
  c_max_rows    constant pls_integer := 50;
  c_max_points  constant pls_integer := 200;

  /**
   * Registers (or re-registers) a custom widget type. Does not commit.
   *
   * @param p_type              Model-facing type name: lower case, 2 to 30 characters,
   *                            letters, digits and underscore. A built-in name and
   *                            item_list are not allowed. Use a short prefix of your own.
   * @param p_provider_package  Package with get_protocol and build_spec (see above).
   *                            Must exist in the schema and have both members.
   */
  procedure register_type(
    p_type             in varchar2,
    p_provider_package in varchar2
  );

  /**
   * Is a type in a normalised, colon separated list?
   */
  function type_in_list(
    p_list in varchar2,
    p_type in varchar2
  ) return boolean;

  /**
   * Removes a registered type. Does not commit. Messages that already hold a widget
   * of that type keep their snapshot.
   */
  procedure unregister_type(
    p_type in varchar2
  );

  /**
   * Reduces a type list to the supported types: lower case, de-duplicated,
   * built-in types first in the order of c_all_types, then registered and enabled
   * types in the order the list names them, colon separated. Unknown entries are
   * dropped, so a list can never enable more than the built-ins and the registry.
   *
   * @param p_types  Colon separated widget types, any case. Null = none.
   * @return The normalised list, or null when no supported type is left.
   */
  function normalize_types(
    p_types in varchar2
  ) return varchar2;

  /**
   * The WIDGET PROTOCOL block for a system prompt. Describes only the enabled
   * types.
   *
   * @param p_types  Colon separated widget types, e.g. 'stat_card:chart'. Null = none.
   * @return The block, or null when no type is enabled.
   */
  function get_protocol(
    p_types in varchar2
  ) return clob;

  /**
   * Cuts an answer into parts: [{"kind":"text","text":...},
   * {"kind":"widget","type":...,"spec":{...}}, ...]. Never raises on bad
   * widgets.
   *
   * @param p_answer      The text of the model.
   * @param p_types       Enabled types, colon separated.
   * @param p_tool_calls  The tool calls of this turn in call order, each
   *                      {"name":"<tool>","args":{...} or text,"output":<parsed json>}.
   *                      A call whose output is not valid JSON has no "output".
   */
  function render(
    p_answer     in clob,
    p_types      in varchar2,
    p_tool_calls in json_array_t default null
  ) return json_array_t;

  /**
   * Emits the 'parts' member of an assistant message into the open apex_json
   * object, from the snapshot render() produced: {kind:"text",text,rejected?} or
   * {kind:"widget",type,spec}. Writes member by member, so the output is valid
   * JSON by construction. A snapshot that does not parse writes nothing.
   *
   * @param p_parts          The stored JSON array of parts.
   * @param p_show_rejected  Emit the 'rejected' reason of a downgraded widget
   *                         (a debug detail: the show_errors flag).
   */
  procedure write_parts(
    p_parts         in clob,
    p_show_rejected in boolean
  );

end uc_ai_chat_widgets;
/
