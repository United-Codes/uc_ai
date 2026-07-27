create or replace package body uc_ai_ptc_runner as

  -- Name of the PURE MLE environment created by scripts/install_ptc_sandbox.sql in
  -- THIS schema. PURE is what actually removes SQL access from the generated code.
  gc_pure_env constant varchar2(128 char) := 'UC_AI_PTC_PURE_ENV';

  -- Hard backstop on serviced tool calls. The real per-run budget lives in
  -- uc_ai_tools_api (the gateway raises when it is exceeded), but a program is
  -- free to catch those errors and keep calling, so the trampoline needs its own
  -- ceiling to stay finite.
  gc_max_iterations constant pls_integer := 1000;

  -- MLE value names exchanged with the program
  gc_v_code  constant varchar2(30 char) := 'uc_ai_code';
  gc_v_state constant varchar2(30 char) := 'uc_ai_state';
  gc_v_tool  constant varchar2(30 char) := 'uc_ai_req_tool';
  gc_v_args  constant varchar2(30 char) := 'uc_ai_req_args';
  gc_v_res   constant varchar2(30 char) := 'uc_ai_res';
  gc_v_err   constant varchar2(30 char) := 'uc_ai_err';
  gc_v_out   constant varchar2(30 char) := 'uc_ai_result';
  gc_v_msg   constant varchar2(30 char) := 'uc_ai_error';
  gc_v_log   constant varchar2(30 char) := 'uc_ai_console';

  /*
   * Bootstrap evaluated before the model's code.
   *
   * Wraps the program in an async function whose only injected capability is
   * callTool(). Because a PURE context has no SQL access, callTool cannot execute
   * anything itself: it queues the request, hands control back to PL/SQL (state
   * "call") and returns a promise that __resume() settles with the tool result.
   * Queueing (rather than a single pending slot) keeps Promise.all([...]) working.
   *
   * Since the call is asynchronous, a forgotten `await` would otherwise hand the
   * program a promise where it expects data. Two layers deal with that (see
   * __add_awaits and __must_await below), so a missing await is repaired when it
   * safely can be and reported precisely when it cannot.
   */
  gc_boot_helpers constant varchar2(4000 char) := q'~
    const __b = require("mle-js-bindings");
    const __q = [];

    // Console output goes nowhere in a dynamic MLE context, so capture it. Models
    // are told to assign `result`, but a program that logs instead of assigning -
    // or one that logs and then throws - would otherwise lose everything it said.
    const __log = [];
    function __capture(prefix) {
      return function () {
        if (__log.length >= 50) { return; }
        const parts = [];
        for (let i = 0; i < arguments.length; i++) {
          const a = arguments[i];
          if (typeof a === "string") { parts.push(a); }
          else { try { parts.push(JSON.stringify(a)); } catch (e) { parts.push(String(a)); } }
        }
        let line = prefix + parts.join(" ");
        if (line.length > 2000) { line = line.slice(0, 2000) + "..."; }
        __log.push(line);
      };
    }
    globalThis.console = { log:   __capture("")
                         , info:  __capture("")
                         , debug: __capture("")
                         , warn:  __capture("[warn] ")
                         , error: __capture("[error] ") };

    // CLOBs arrive as LOB objects, not strings
    function __str(v) {
      if (v === null || v === undefined) { return null; }
      if (typeof v === "string") { return v; }
      return v.getData ? v.getData() : String(v);
    }

    // Layer 1: insert the missing `await` before a bare callTool( call.
    // Skips comments and string/template literals so their contents are never
    // rewritten, and leaves member calls (obj.callTool(...)) alone. If the result
    // does not parse - the classic case is an injected await inside a non-async
    // callback - the caller falls back to the untouched source.
    function __add_awaits(src) {
      const ident = /[A-Za-z0-9_$]/;
      let out = "", i = 0;
      const n = src.length;
      while (i < n) {
        const c = src[i];
        if (c === "/" && src[i + 1] === "/") {
          const j = src.indexOf("\n", i); const e = j < 0 ? n : j;
          out += src.slice(i, e); i = e; continue;
        }
        if (c === "/" && src[i + 1] === "*") {
          const j = src.indexOf("*/", i + 2); const e = j < 0 ? n : j + 2;
          out += src.slice(i, e); i = e; continue;
        }
        if (c === '"' || c === "'" || c === "`") {
          let j = i + 1;
          while (j < n) {
            if (src[j] === "\\") { j += 2; continue; }
            if (src[j] === c) { j++; break; }
            j++;
          }
          out += src.slice(i, j); i = j; continue;
        }
        if (c === "c" && src.startsWith("callTool", i)) {
          const prev = i > 0 ? src[i - 1] : "";
          let k = i + 8;
          while (k < n && /\s/.test(src[k])) { k++; }
          if (src[k] === "(" && prev !== "." && !ident.test(prev)) {
            if (!/(^|[^A-Za-z0-9_$])await$/.test(out.replace(/\s+$/, ""))) { out += "await "; }
            out += "callTool"; i += 8; continue;
          }
        }
        out += c; i++;
      }
      return out;
    }

    // Layer 2: for what a rewrite cannot reach (aliases like [1,2].map(callTool),
    // or a call inside a template literal), fail loudly instead of silently using a
    // promise as data. Awaiting, .then() and Promise.all() stay untouched.
    function __must_await(p) {
      return new Proxy(p, {
        get: function (target, key) {
          if (key === "then" || key === "catch" || key === "finally" || key === "constructor") {
            const v = target[key];
            return typeof v === "function" ? v.bind(target) : v;
          }
          if (key === Symbol.toStringTag) { return "Promise"; }
          throw new Error("callTool() is asynchronous - write: await callTool(...)");
        }
      });
    }

  ~';

  -- second half: the callTool bridge itself and the program launcher
  gc_boot_machinery constant varchar2(4000 char) := q'~
    function __publish() {
      const h = __q[0];
      __b.exportValue("uc_ai_req_tool", h.name);
      __b.exportValue("uc_ai_req_args", h.args);
      __b.exportValue("uc_ai_state", "call");
    }

    function callTool(name, args) {
      return __must_await(new Promise(function (resolve, reject) {
        __q.push({ name:  String(name)
                 , args:  JSON.stringify(args === undefined || args === null ? {} : args)
                 , res:   resolve
                 , rej:   reject });
        __publish();
      }));
    }

    globalThis.__resume = function () {
      const err = __str(__b.importValue("uc_ai_err"));
      const raw = __str(__b.importValue("uc_ai_res"));
      const h   = __q.shift();
      __b.exportValue("uc_ai_state", "run");
      if (err) {
        h.rej(new Error(err));
      } else {
        let v = null;
        // Tools normally return JSON; fall back to the raw string for plain-text tools.
        if (raw !== null && raw !== "") { try { v = JSON.parse(raw); } catch (e) { v = raw; } }
        h.res(v);
      }
      if (__q.length > 0) { __publish(); }
    };

    (function () {
      const src = __str(__b.importValue("uc_ai_code"));
      const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
      const tail = "\n;return (typeof result === 'undefined') ? null : result;";
      let program;
      try {
        program = new AsyncFunction("callTool", __add_awaits(src) + tail);
      } catch (e) {
        // the rewrite did not parse (e.g. await inside a non-async callback):
        // run what the model actually wrote and report ITS error, not ours
        try {
          program = new AsyncFunction("callTool", src + tail);
        } catch (e2) {
          __b.exportValue("uc_ai_state", "error");
          __b.exportValue("uc_ai_error", "syntax error: " + (e2 && e2.message ? e2.message : String(e2)));
          __b.exportValue("uc_ai_console", null);
          return;
        }
      }
      program(callTool).then(
        function (v) {
          __b.exportValue("uc_ai_state", "done");
          if ((v === null || v === undefined) && __log.length > 0) {
            // nothing assigned to `result`, but the program printed something
            __b.exportValue("uc_ai_result", "console output:\n" + __log.join("\n"));
            return;
          }
          __b.exportValue("uc_ai_result",
            v === null || v === undefined ? null : (typeof v === "string" ? v : JSON.stringify(v)));
        },
        function (e) {
          __b.exportValue("uc_ai_state", "error");
          __b.exportValue("uc_ai_error", (e && e.message ? e.message : String(e)));
          __b.exportValue("uc_ai_console", __log.length > 0 ? __log.join("\n") : null);
        });
    })();
  ~';


  -- Errors are handed to the model as data so it can fix its program and retry.
  -- Anything the program logged before it failed goes along: that is the only
  -- debugging information the model has for its next attempt.
  function error_result(
    p_message in varchar2
  , p_console in clob default null
  ) return clob
  as
    l_err json_object_t := json_object_t();
  begin
    l_err.put('error', p_message);
    l_err.put('hint', 'Fix the program and call the code tool again. Every callTool() must be awaited, and only the exact tool codes listed in the tool description are callable.');
    if p_console is not null and sys.dbms_lob.getlength(p_console) > 0 then
      l_err.put('console', p_console);
    end if;
    return l_err.to_clob;
  end error_result;


  -- A PURE context is mandatory: without it the generated JavaScript could reach
  -- SQL. The environment lives in this schema; fall back to the qualified name in
  -- case an unqualified lookup does not resolve for a definer's-rights caller.
  function create_pure_context return sys.dbms_mle.context_handle_t
  as
  begin
    return sys.dbms_mle.create_context(environment => gc_pure_env);
  exception
    -- @dblinter ignore(G-5040): retried with the qualified environment name below
    when others then
      return sys.dbms_mle.create_context(environment => $$plsql_unit_owner || '.' || gc_pure_env);
  end create_pure_context;


  function run_code(
    p_code in clob
  ) return clob
  as
    l_ctx    sys.dbms_mle.context_handle_t;
    l_state  varchar2(30 char);
    l_tool   varchar2(255 char);
    l_args   clob;
    l_res    clob;
    l_err    varchar2(4000 char);
    l_result  clob;
    l_console clob;
    l_calls   pls_integer := 0;
  begin
    l_ctx := create_pure_context;

    begin
      sys.dbms_mle.export_to_mle(l_ctx, gc_v_state, 'run');
      sys.dbms_mle.export_to_mle(l_ctx, gc_v_code, p_code);
      sys.dbms_mle.eval(l_ctx, 'JAVASCRIPT', gc_boot_helpers || chr(10) || gc_boot_machinery);

      -- Service the program's tool calls until it finishes, fails, or stalls.
      <<trampoline>>
      loop
        sys.dbms_mle.import_from_mle(l_ctx, gc_v_state, l_state);
        exit trampoline when l_state is null or l_state != 'call';

        l_calls := l_calls + 1;
        if l_calls > gc_max_iterations then
          sys.dbms_mle.drop_context(l_ctx);
          return error_result('program exceeded ' || gc_max_iterations || ' tool calls and was stopped');
        end if;

        sys.dbms_mle.import_from_mle(l_ctx, gc_v_tool, l_tool);
        sys.dbms_mle.import_from_mle(l_ctx, gc_v_args, l_args);

        l_res := null;
        l_err := null;
        begin
          -- The gateway enforces this run's allow-list, call budget and the
          -- per-tool-call hook, then executes the tool with UC AI's privileges.
          l_res := uc_ai_ptc_api.call_tool_json(
                     p_tool_code => l_tool
                   , p_args_json => l_args
                   );
        exception
          -- @dblinter ignore(G-5040): the failure is handed to the program as a rejected callTool so the model can react
          when others then
            l_err := substr(sqlerrm, 1, 4000);
        end;

        sys.dbms_mle.export_to_mle(l_ctx, gc_v_res, l_res);
        sys.dbms_mle.export_to_mle(l_ctx, gc_v_err, l_err);
        sys.dbms_mle.eval(l_ctx, 'JAVASCRIPT', '__resume();');
      end loop trampoline;

      case l_state
        when 'done' then
          sys.dbms_mle.import_from_mle(l_ctx, gc_v_out, l_result);
          -- Never hand back NULL: a tool result becomes the content of a tool
          -- message, and OpenAI-compatible APIs reject a null content (HTTP 422).
          -- Saying so explicitly also tells the model what it forgot.
          if l_result is null or sys.dbms_lob.getlength(l_result) = 0 then
            l_result := error_result('the program finished without assigning a value to `result`');
          end if;
        when 'error' then
          sys.dbms_mle.import_from_mle(l_ctx, gc_v_msg, l_err);
          sys.dbms_mle.import_from_mle(l_ctx, gc_v_log, l_console);
          l_result := error_result('code execution failed: ' || l_err, l_console);
        else
          -- the program is still suspended on something that will never settle
          l_result := error_result('the program never finished - it awaited something other than callTool()');
      end case;

      sys.dbms_mle.drop_context(l_ctx);
    exception
      -- @dblinter ignore(G-5040): re-raised after releasing the context; converted to data below
      when others then
        sys.dbms_mle.drop_context(l_ctx);
        raise;
    end;

    return l_result;
  exception
    -- @dblinter ignore(G-5040): intentional catch-all - every code-mode failure is turned into JSON data below, not propagated
    -- @dblinter ignore(G-5080): the PL/SQL backtrace is deliberately NOT surfaced to the model; only a compact error message is returned
    when others then
      -- Surface the failure to the model AS DATA (a JSON error) rather than
      -- raising, so a single mistake in the generated program (a JS error, a
      -- disallowed tool, or an exceeded budget) becomes a tool_result the model
      -- can read and correct on its next turn instead of aborting the run.
      return error_result('code execution failed: ' || sqlerrm);
  end run_code;

end uc_ai_ptc_runner;
/
