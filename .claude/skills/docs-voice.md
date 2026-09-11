# Docs voice: clear, direct, and helpful

Use this guide when writing or editing pages under `docs/src/content/docs/`,
or when reviewing their tone. Apply it together with the `simple-english` skill
for sentence mechanics. For course structure, also read
[write-tutorial-guide.md](write-tutorial-guide.md).

The landing page (`index.mdx`) and `guides/use-cases.mdx` can retain persuasive
language. Release history is a published record: preserve dates, versions,
feature names, and historical meaning.

## Target voice

Write as a helpful colleague who explains the task clearly and respects the
reader's time. State what to do, why it is needed, and what result to expect.
Use familiar words and complete sentences. A friendly tone does not need jokes,
punchlines, or comments about the reader's ability.

Introduce a concept with a short explanation when the reader needs it. Keep
reasons that help someone make a decision or understand a result. Remove text
that only announces importance, repeats a conclusion, or advertises the product.

Do not make the prose so terse that the reader must guess missing connections.
Technical terms are appropriate when they are precise; explain unfamiliar ones
at first use. Do not replace them with vague words such as “thing” or “shape.”

## Name the task or topic in headings

Headings also appear in the “On this page” navigation. Each heading must identify
its content without requiring the reader to read the section first.

Use action headings for procedures and topic headings for explanations. Apply
this rule to page titles, lesson titles, callouts, and next-lesson links too.

| Avoid | Use |
| --- | --- |
| Every run writes its own history | Read the execution log |
| Who ran what | Review session activity |
| Put it in front of a person | Add an APEX chat interface |
| Every branch, with no model | Test the credit-note rules |
| The transaction is yours | Commit or roll back the changes |
| A question the pasted rows cannot answer | Ask about remaining credit |
| Ship it | Deploy the agent configuration |
| Run it | Run the agent with a contract ID |

Generic headings such as “The problem” and “What changed” often hide the subject.
Replace them with the topic, or delete the section if it only repeats earlier text.
“Verification” can remain when it consistently identifies a lesson's final checks.
Troubleshooting headings can name a concrete symptom, such as “The model called
no tool.”

Before renaming an existing heading, search for its anchor with `rg`. Update
inbound links and run the docs build. Preserve the anchor when changing it would
break a public link that must remain supported.

## Explain without judging

Give the fact or instruction directly. Avoid attention commands, rhetorical
questions, imagined reader reactions, and judgments about earlier approaches.
Do not repeatedly frame explanations as “Without X ... With X ...”. Explain the
mechanism and its effect. Use a comparison when the reader actually needs to
choose between alternatives.

| Avoid | Use |
| --- | --- |
| Read `tool_output` before you blame the model. | Read `tool_output` to see what the handler returned. |
| `WRONG_CONTRACT` is the row to read twice. | The handler rejected an invoice from another contract. |
| Turn 2 never said `INV-1001`. The session did. | The second call uses the conversation history to identify `INV-1001`. |
| Without the trace, you change the prompt and hope. | The trace shows which tools ran and what they returned. |
| This is the check that matters. | Describe what the check establishes. |
| This is easy. | Give the steps. |

Commands such as “Run this block” and “Compare the returned amount with the
invoice total” direct work and are useful. “Look again” and “Read that carefully”
usually add no information.

## Keep claims precise

Limit a conclusion to what the code, data, or recorded run supports. Shortening
an explanation must not strengthen its claim.

- A successful example does not establish that every run succeeds.
- Missing data in one prompt does not establish that the data cannot fit in a prompt.
- A read tool can return incorrect data or expose data. Do not call it safe merely
  because it does not write rows.
- Describe which rule a handler enforces and where its trusted values come from.
  Do not imply that one filter establishes all application authorization.
- Preserve uncertainty and qualifications when they affect meaning. Removing
  “I think” must not turn an opinion into a fact.
- Give a measured value and its context instead of quality claims such as
  “powerful,” “seamless,” or “the most reliable.”

Use recorded output as evidence. Preserve the original response, model, date,
and timing. If an old recording no longer matches the procedure, remove it or
explain the different starting state. Label expected behavior as expected
behavior; never manufacture a replacement recording.

## Make the procedure complete

Before presenting code, say whether the reader must run it or whether it is an
excerpt. If a linked script performs the steps, state what it does and which
additional blocks the reader must run. Avoid requiring both without explanation.

Include the prerequisites needed for the current task: working directory,
connection, required objects, script order, and values the reader must supply.
Show how to obtain or assign placeholders such as a session ID.

Follow data changes across lessons. A committed insert remains present in the
next lesson. Explain repeat runs, resets, and different starting states where
they affect the result. Put a reset's effect before the reset command.

Match displayed output to the displayed command. Label omitted columns and
illustrative output. Distinguish fixed values from model-dependent wording,
filenames, timings, token counts, and generated IDs. Explain how readers can
use their own returned values in the next step.

Keep one explanation of each point at the place where the reader needs it.
A lesson introduction, result explanation, and takeaway list do not all need
the same summary. Retain a short recap when it helps the reader complete or
check the task.

## Preserve technical meaning and repository conventions

Keep API names, identifiers, commands, error messages, and quoted model output
exact during a language edit. Fix code only when the task includes a technical
correction. Validate that correction separately from the prose review.

Use the repository's fixed terminology in prose: “configuration,” “call” for a
procedure, “run” for an agent execution, “delete” for data, “error” for a raised
exception, and “failure” for an operation that did not finish. Use “make sure
that” for the check/verify/confirm concept where a verb is needed. Preserve
technical names that use other terms.

Match the surrounding Markdown style and paragraph wrapping. Keep links to
reference material for detail that the current task does not need.

## Review before completion

1. Read the headings alone. Can a reader locate each task and concept?
2. Read the full prose. Remove judgments, punchlines, repeated contrasts, and
   sentences that only announce importance. Phrase searches are aids, not a review.
3. Follow the instructions in order, including state carried from earlier lessons.
   Make sure that every required action and replacement value is explained.
4. Compare commands with their output. Preserve recorded evidence and distinguish
   it from expected behavior. Make sure that conclusions stay within the evidence.
5. Apply the `simple-english` sentence checks. Retain complete grammar and the
   qualifications needed for accuracy.
6. Inspect the diff for changed code, quotes, links, and unrelated edits. After
   documentation changes, run `bun run build` from `docs/` to check MDX and links.

For a review-only request, report findings and suggested rewrites. For an editing
request, apply the authorized language and structural fixes, including headings
and redundant sections, and repair affected links.
