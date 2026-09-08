---
name: uc-ai-agent-memory
description: Use when an AI agent must remember something across conversations in Oracle PL/SQL with UC AI — enabling the MEMORY tool with uc_ai_memory.enable_for_agent, choosing a store scope (agent, user, session, shared, global, context), one memory per document with a run-context key, steering what the agent records through the system prompt, seeding or reading files with put_file/get_file/list_files, size caps and expire_files housekeeping, the uc_ai_v_memory_files view, or using memory outside an agent run with set_store.
---

# UC AI Agent Memory — Knowledge That Survives the Session

An agent with memory stores and reads knowledge across conversations. It gets a virtual filesystem with the root `/memories`, held as CLOBs in Oracle tables. The `MEMORY` tool can `view`, `create`, `str_replace`, `insert`, `delete`, and `rename` the files in it.

The tool follows the command set of the [Anthropic memory tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool), as a normal UC AI function tool, so it works with **every provider**. The installer creates the one `MEMORY` tool row, and that row serves every agent — the tool resolves the store of the caller at each call.

Memory needs an agent with a prompt profile (see the `uc-ai-multi-agent` skill). For a plain `generate_text` call, read [Memory outside an agent run](#memory-outside-an-agent-run).

## Enabling memory

```sql
begin
  uc_ai_memory.enable_for_agent('SUPPORT_AGENT');
  commit;
end;
/
```

That one call does three things:

1. It writes the row of the agent in `uc_ai_memory_config`, with the scope and the size caps.
2. It adds the `memory` tool tag and `g_enable_tools` to the `model_config_json` of the prompt profile, so the tool reaches the model.
3. From the next **new** session, UC AI appends the MEMORY PROTOCOL block to the rendered system prompt: view `/memories` first, record progress during the work, and expect an interruption.

The full signature:

```sql
procedure enable_for_agent(
  p_agent_code      in uc_ai_agents.code%type,
  p_scope           in varchar2 default uc_ai_memory.c_scope_agent,
  p_store_code      in varchar2 default null,   -- required for 'shared', namespace for 'context'
  p_context_key     in varchar2 default null,   -- required for 'context'
  p_update_profile  in boolean  default true,   -- also add the tool tag to the profile
  p_max_file_chars  in number   default null,   -- default 100000
  p_max_store_chars in number   default null,   -- null = unlimited
  p_max_files       in number   default null    -- default 1000
);
```

`uc_ai_memory.disable_for_agent(p_agent_code, p_remove_tool_tag, p_drop_store)` turns it off again. `p_drop_store => true` also deletes the own stores of the agent. A shared, global, or session store is never dropped.

## Scopes: which agents and users share one memory

Use the constants, not string literals: `uc_ai_memory.c_scope_agent`, `c_scope_user`, `c_scope_session`, `c_scope_shared`, `c_scope_global`, `c_scope_context`.

| Scope | One store per… | Use for |
|-------|----------------|---------|
| `agent` | agent code *(default)* | knowledge the agent accumulates. All users share it |
| `user` | agent + `created_by` | one memory per signed-in end user (read the caution below) |
| `session` | conversation session | scratch memory that must not outlive the conversation |
| `shared` | named store (`p_store_code`) | several agents on one knowledge base |
| `global` | whole installation | one common memory |
| `context` | value of a run-context key | one memory per document, case, or tenant |

```sql
-- per end user
uc_ai_memory.enable_for_agent('SUPPORT_AGENT', p_scope => uc_ai_memory.c_scope_user);

-- two agents on one named store
uc_ai_memory.enable_for_agent('RESEARCH_AGENT', p_scope => uc_ai_memory.c_scope_shared, p_store_code => 'TEAM_KB');
uc_ai_memory.enable_for_agent('WRITER_AGENT',   p_scope => uc_ai_memory.c_scope_shared, p_store_code => 'TEAM_KB');
```

**Caution with `user` scope.** It keys the store on `created_by`, which is `coalesce(APEX$SESSION.APP_USER, the database user)`. Each person gets a private memory only when each person has an own authenticated APEX session. In a public APEX application every visitor is the same APEX user, and through an ORDS endpoint or a scheduler job every caller is the same database user — all of them then share **one** store. To key on your own identifier, use the `context` scope.

### One memory per document: the context scope

The `context` scope keys the store on a value of the run context (see the `uc-ai-tools` skill):

```sql
uc_ai_memory.enable_for_agent(
  p_agent_code  => 'DOC_AGENT'
, p_scope       => uc_ai_memory.c_scope_context
, p_context_key => 'document_id'
);
```

Every run that starts with `p_run_context => json_object_t('{"document_id":"7"}')` resolves to the store `context:DOC_AGENT:document_id:7`. A run for document 8 gets its own store, and neither run reads the files of the other. Name a `p_store_code` to let several agents share one memory per value — both agents then resolve to `context:DOCS:document_id:7`:

```sql
uc_ai_memory.enable_for_agent('DOC_CHAT',    p_scope => uc_ai_memory.c_scope_context
, p_context_key => 'document_id', p_store_code => 'DOCS');
uc_ai_memory.enable_for_agent('DOC_SUMMARY', p_scope => uc_ai_memory.c_scope_context
, p_context_key => 'document_id', p_store_code => 'DOCS');
```

Two rules apply to the value:

- **The run must supply the key.** UC AI checks it before the run starts and raises `ORA-20426` when the key is missing, so the run stops instead of reading an empty memory.
- The value takes at most 200 characters from `A-Z`, `a-z`, `0-9`, underscore, dot, and hyphen. The store key is built by concatenation, so UC AI refuses any other value.

## Steering what the agent records

The MEMORY PROTOCOL names the kinds of things that belong in a memory: decisions, preferences, learnings, and progress. It cannot know which information matters in your domain — put that in the `system_prompt_template` of the prompt profile:

```text
MEMORY
Record what the next reader cannot get from the tables: why a machine behaves
the way it does, what we already tried, and what the customer prefers.
Keep the current state apart from the long history.
Start every line with the date as YYYY-MM-DD.
When a line stops being true, replace it. Never append a correction below it.
Never record a phone number, a home address, or any other personal data.
```

Add it with the row-based update, which keeps the model configuration and the memory tool tag as they are (see the `uc-ai-prompt-profiles` skill):

```sql
declare
  l_profile uc_ai_prompt_profiles%rowtype;
begin
  l_profile := uc_ai_prompt_profiles_api.get_prompt_profile(p_code => 'support_agent_profile');
  l_profile.system_prompt_template := l_profile.system_prompt_template || chr(10) || chr(10) || :memory_rules;
  uc_ai_prompt_profiles_api.update_prompt_profile(l_profile);
  commit;
end;
/
```

The agent picks its own file names, which is enough for a file that only the agent writes and reads. Name an exact path when somebody else touches the file: a person who seeds a note with `put_file`, a second agent on the same store, or a report that reads one file. New prompt rules take effect on the next new session.

## Caps, housekeeping, and direct access

`uc_ai_memory_config` caps the growth of a store: `max_file_chars` (default 100,000), `max_files` (default 1,000), and the optional `max_store_chars`. A write past a cap returns an error text that asks the model to merge or delete old files.

```sql
begin
  uc_ai_memory.expire_files(p_days => 180);   -- files untouched for 180 days; p_store_id for one store
  commit;
end;
/
```

The view `uc_ai_v_memory_files` shows what a store holds. Manage files yourself with `list_files`, `get_file`, `put_file`, `delete_file`, and `clear_store_files`. All of them take a store id from `resolve_store_id`:

```sql
declare
  e_no_store exception;
  pragma exception_init(e_no_store, -20423);
  l_store_id number;
begin
  l_store_id := uc_ai_memory.resolve_store_id(
    p_scope         => uc_ai_memory.c_scope_context
  , p_agent_code    => 'DOC_AGENT'
  , p_context_key   => 'document_id'
  , p_context_value => '7'
  );
  uc_ai_memory.put_file(l_store_id, '/memories/reference.md', :content);
  commit;
exception
  when e_no_store then
    null;  -- the agent has not run yet, so the store does not exist
end;
/
```

## Memory outside an agent run

A plain `generate_text` call points the session at a named store first:

```sql
begin
  uc_ai_memory.set_store('MY_NOTES');          -- session-level override
  uc_ai.g_enable_tools := true;
  uc_ai.g_tool_tags    := apex_t_varchar2(uc_ai_memory.c_tool_tag);
  -- ... uc_ai.generate_text(...)
  uc_ai_memory.clear_store;
end;
/
```

Such a call renders no prompt profile and gets no MEMORY PROTOCOL block. Add it to your system prompt with `uc_ai_memory.get_memory_protocol`.

## Pitfalls

- **A store exists after its first use.** UC AI creates it on the first write, so `resolve_store_id` raises `ORA-20423` for an agent that has never run. A seeding script must handle that error, or do one throwaway run first.
- **Memory takes full effect on the next new session.** An open conversation keeps the system prompt it started with. The tool itself works at once.
- **Errors are messages, not exceptions.** The tool returns a text such as "The path … does not exist", and the model reacts to it. A memory error never aborts a run. Only the admin and config procedures raise.
- **A context-scoped run without its key fails at the start** with `ORA-20426`. Fine to rely on: a resolution failure would otherwise reach the model as text, and the model would report an empty memory while the data sits in the store.
- **Writes join the transaction of the caller.** A rollback of the run rolls the memory back with it. `enable_for_agent` and the file procedures do not commit.
- **Nothing commits for you.** Add a `commit` after `enable_for_agent`, `put_file`, and `expire_files`.
- **Paths stay under `/memories`.** The tool rejects `..`, a backslash, and URL-encoded traversal.
- **Parallel writes to one file serialize** on row locks. The last committed write wins.

## Full documentation

- Agent memory guide: https://www.united-codes.com/products/uc-ai/docs/guides/agent-memory/
- The run context (for the `context` scope): https://www.united-codes.com/products/uc-ai/docs/guides/tools/#the-run-context
- Prompt profiles: https://www.united-codes.com/products/uc-ai/docs/guides/prompt-profiles/
- Anthropic memory tool contract: https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
