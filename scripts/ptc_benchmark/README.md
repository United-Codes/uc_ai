# Code-mode benchmark

Measures what [programmatic tool calling](https://www.united-codes.com/products/uc-ai/docs/guides/programmatic-tool-calling/)
("code mode") actually buys you, per provider, on a task that is deliberately bad
for classic tool calling.

It reproduces the expense-analysis scenario from Anthropic's
[PTC cookbook](https://platform.claude.com/cookbook/tool-use-programmatic-tool-calling-ptc)
as UC AI tools: 8 engineers, 15 metadata-rich expense rows each (~2,600 tokens per
employee), a 5,000 USD standard travel budget and two custom budgets — one high
enough to keep an employee under, one low enough to push an employee over who would
otherwise be fine. Answering it needs 17 tool calls the classic way.

The same question is then asked twice per provider: once with code mode off, once
with it on. Nothing in the prompt asks for a program, so the run also shows whether
a model reaches for one on its own.

## Requirements

- Oracle 23ai with the code-mode sandbox installed (`@scripts/install_ptc_sandbox.sql`)
- API keys for the providers you want to test, returned by your `uc_ai_get_key` function
- **Real, paid LLM calls**: about 20 requests per pass. The classic cases are the
  expensive ones (~25k–35k tokens each), so pick cheap models if you change the list.

## Usage

```sql
@scripts/ptc_benchmark/setup.sql    -- fixture + tools + driver package
@scripts/ptc_benchmark/run.sql      -- one pass over all providers
@scripts/ptc_benchmark/cleanup.sql  -- remove everything again
```

LLMs vary between runs, so a single pass measures the model's mood as much as its
ability. For anything you want to quote, run several passes:

```sql
begin uc_ai_ptc_bench.run_all(p_passes => 3); end;
/

-- or just one provider
begin uc_ai_ptc_bench.run_all(p_provider => uc_ai.c_provider_google); end;
/
```

## Output

One line per case:

```
expected answer: 103,104,105,106,108
--- pass 1 of 1 ---
openai gpt-5-mini              | classic | program: no  | calls: 17 | tokens:   24340 |  15.3s | 103,104,105,106,108 | correct
openai gpt-5-mini              | code    | program: yes | calls:  1 | tokens:    2455 |  13.4s | 103,104,105,106,108 | correct
```

- **program** — whether the model actually used the code tool
- **calls** — tool calls in the conversation (a whole program counts as one)
- **tokens** — total tokens for the conversation, the number code mode is meant to reduce
- **correct** — the answer is graded automatically against the deterministic fixture,
  which is why the prompt asks the model to end with a `RESULT:` line

The models are configured in `uc_ai_ptc_bench.run_all` — edit that list to test
other providers or models.
