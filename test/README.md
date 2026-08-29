# UC AI Tests

Example usage:

```sql
-- single test

set serveroutput on
begin
  ut.run('test_uc_ai_openai.tool_clock_in_user');
end;
/

-- all tests in the package
set serveroutput on
begin
  ut.run('test_uc_ai_openai');
end;
```

## LLM-free wire tests

`test_uc_ai_wire` runs `generate_text` / `generate_embeddings` end to end without a
network. `uc_ai_http` is the one place the providers send HTTP; the suite registers
`uc_ai_test_http_mock` as its transport, which records every request (URL, headers,
body, credential) and answers with the next queued response.

The recorded requests and responses live in `test/samples/**/*.json`. They are
compiled into the `uc_ai_test_samples` package by

```bash
bash scripts/generate_test_samples.sh   # or: make generate
```

so a test can say "the request UC AI built must equal
`openai/chat/4-structured-output-request`". Change the JSON, regenerate, recompile
`test/uc_ai_test_samples.pkb`. Never edit the generated package.

`uc_ai_http.set_transport` only exists in a debug build. Compile it once per test
schema before running the wire suites:

```bash
sql -name local-23ai-uc_ai @scripts/enable_test_transport.sql
```

`scripts/run_tests_free.sql` does this itself. Without the flag the wire tests fail
with `ORA-20502: uc_ai_http.set_transport requires a build compiled with
plsql_ccflags = 'UC_AI_DEBUG:TRUE'`. Never set the flag in production: it compiles
in the dynamic call that lets a registered package answer provider requests.

Install order for the test side: `uc_ai_test_samples`, `uc_ai_test_http_mock`,
then `test_uc_ai_wire`, `test_uc_ai_wire_2`, `test_uc_ai_wire_3` (each one calls helpers of
the one before). The whole LLM-free set runs with `make test-free`.
