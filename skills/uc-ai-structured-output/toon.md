# TOON — Token-Oriented Object Notation

TOON is a compact, human-readable, **lossless** encoding of the JSON data model designed for LLM *input*. It combines YAML-style indentation for nested objects with a CSV-style tabular layout for uniform arrays. Use JSON programmatically, encode it as TOON just before putting it into the prompt.

## Why

- **Cost**: fewer tokens per row of data means cheaper calls
- **Context**: more room for actual content in the context window
- **Parsing**: explicit structure (`[count]{fields}`) helps models validate what they read

## When to use — and when not

| Scenario | Recommendation |
|----------|----------------|
| Uniform arrays of objects (same fields per row) | Use TOON — maximum savings |
| Tabular query results (`json_arrayagg`) | Use TOON — CSV-like efficiency |
| Simple flat objects | Use TOON — cleaner than JSON |
| Deeply nested, irregular structures | Consider plain JSON |
| Non-uniform arrays with varied schemas | Consider plain JSON |
| Data the LLM must **return** | Use JSON — that is structured output's job (`p_response_json_schema`, see `SKILL.md` in this skill) |

## API

Three overloads in `uc_ai_toon`; all return `null` for `null` input:

```sql
function to_toon(p_json_object in json_object_t) return clob;
function to_toon(p_json_array  in json_array_t)  return clob;
function to_toon(p_json_string in clob)          return clob;
```

## Format at a glance

```
name: Alice                      -- object: key: value
user:                            -- nested object: indentation (2 spaces)
  email: bob@ex.com
[3]: 1,2,3                       -- primitive array: inline with count
[2]{id,active}:                  -- uniform object array: tabular
  1,true
  2,false
[2]:                             -- irregular array: dash notation
  - a: 1
  - c: 3
```

Nulls are `null`, booleans `true`/`false`, empty arrays `key[0]:`, empty objects `key:`, strings with special characters are quoted and escaped.

### Before / after

The same three rows as JSON vs. TOON — the field names appear once instead of once per row:

```json
[{"id":10,"name":"Administration","mgr":200},
 {"id":30,"name":"Purchasing","mgr":114},
 {"id":90,"name":"Executive","mgr":100}]
```

```
[3]{id,name,mgr}:
  10,Administration,200
  30,Purchasing,114
  90,Executive,100
```

## End-to-end: query → to_toon → prompt context

Aggregate rows with `json_arrayagg` (uniform objects produce the tabular format), convert, and embed in the prompt:

```sql
declare
  l_products  json_array_t;
  l_toon_data clob;
  l_result    json_object_t;
begin
  select json_arrayagg(
           json_object(
             'id'    value product_id,
             'name'  value product_name,
             'price' value list_price,
             'stock' value quantity_on_hand
           )
           order by product_name
         )
    into l_products
    from products p
    join inventories i on p.product_id = i.product_id
   where category_id = 1
   fetch first 10 rows only;

  -- Convert to TOON for token efficiency
  l_toon_data := uc_ai_toon.to_toon(l_products);

  -- API key: uc_ai_get_key function or uc_ai_openai.g_apex_web_credential := 'OPENAI';
  l_result := uc_ai.generate_text(
    p_system_prompt => 'You are analyzing product inventory data provided in TOON format (a compact JSON representation).'
  , p_user_prompt   => 'Here is our current electronics inventory:' || chr(10) ||
                       l_toon_data || chr(10) || chr(10) ||
                       'Which products are running low on stock (less than 10 units)?'
  , p_provider      => uc_ai.c_provider_openai
  , p_model         => uc_ai_openai.c_model_gpt_4o_mini
  );

  dbms_output.put_line(l_result.get_clob('final_message'));
end;
/
```

Single rows work the same way with `json_object(...)` into a `json_object_t`, or pass a JSON string CLOB directly to the third overload.

Tip: tell the model in the system prompt that the data is TOON-formatted — one sentence is enough.

## Full documentation

- TOON guide: https://www.united-codes.com/products/uc-ai/docs/guides/toon/
