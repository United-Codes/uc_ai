# Extras

Three scripts that are not part of the seven lessons of **Build an Agent**. Each
one builds on the desk the course leaves behind, and each one is independent of
the other two. Run the course first.

| Script | What it adds |
| --- | --- |
| `07_schema.sql` | A response schema on the prompt profile, so the desk answers with a JSON object that a page can render field by field. |
| `08_apex_job.sql` | A request table and a background job, so a page can ask the desk without waiting for the answer. The [APEX Chat plug-in](https://www.united-codes.com/products/uc-ai/docs/guides/apex-chat-plugin/) does this for you. |
| `09_hook.sql` | An execution hook that refuses the write tool outside office hours and writes one audit row for each run. See the [execution hooks guide](https://www.united-codes.com/products/uc-ai/docs/guides/execution-hooks/). |

`00_teardown.sql` in the parent directory removes what these scripts create.
