# Write a Tutorial Guide

How to plan and write a multi-page, hands-on tutorial series for the UC AI docs
(a "course": several short lessons that build one working thing end to end).
Captures the approach that produced the "Build an Agent" series, including the
review steps that changed the plan and the mistakes that review caught.

Use this for a *tutorial* (one thread, one artifact, ordered lessons). Do not use
it for a *reference guide* (one topic, entered from a search result, read in any
order). The two have opposite rules, and mixing them is the failure mode this
skill exists to prevent.

## Trigger

When asked to plan or write a guide, tutorial, course, lesson series, or
"step-by-step docs" for UC AI — anything where the reader follows several pages
in order and ends with something that runs.

## The rule that matters most

**A tutorial is a thread, not a second copy of the reference.**

Before writing a single page, grep the existing guides for every topic you plan
to teach. The UC AI reference guides are long and dense (`tools.mdx` ~550 lines,
`prompt-profiles.mdx` ~690 lines) and they already contain most individual
mechanics. A lesson that re-explains `create_tool_from_schema` loses to the
reference guide, because the reference is denser and the reader knows it.

**Grep by concept, not by identifier, and then open the file.** Counting
identifier hits per file is not a redundancy check and it will lie to you. A real
mistake from this workflow: a `grep -c` over the trace-table names returned "2
mentions" for a guide, which read as *mentioned in passing*, so the plan claimed
"no page teaches this" and built a lesson on it. The page in fact had a
`### Conversation message log` section with the full column table and almost the
exact query the lesson planned. Always:

```bash
# headings own topics; identifiers only mention them
grep -rn "^#\{2,3\} " docs/src/content/docs/ | grep -i "<topic>"
```

then read the sections that come back. Assume a topic IS covered until you have
read the candidate pages and can say what your delta is.

The tutorial's unique value is:

- **the thread** — one artifact that survives every lesson and gets better
- **the topics no reference page covers** — for UC AI these were: debugging when
  the model misbehaves, what it costs in money, running it from an APEX page,
  and regression-testing a non-deterministic agent

So: teach the mechanic in the smallest form that serves the thread, then link
out with "Full reference: [guide]". Spend the reclaimed space on the four gaps.

## Steps

### 1. Ground yourself in the real API before proposing anything

Read the package **specs**, not the docs, for every API the tutorial will touch:

```bash
grep -n "^\s*\(procedure\|function\)" src/packages/uc_ai_<pkg>.pks
```

Then verify each behavioural claim in the **body**. Every review cycle so far has
caught at least one confident-but-wrong assumption. Examples that were wrong:

- "memory `user` scope is per end user" — it keys on `created_by`, the DB/APEX
  user (`uc_ai_memory.pkb:393`). For a business identity you need
  `p_scope => 'context'` with a `p_context_key`.
- "the run context fills prompt placeholders" — true, but only in the agent
  layer (`uc_ai_agent_exec_api.pkb:24`, `effective_prompt_params`), not in
  `execute_profile`, and input parameters win over context keys.
- "UC AI tracks cost" — it tracks **tokens** only. There is no price column in
  `src/tables/install.sql`. Never write "cost" where you mean tokens.
- Base tables vs. contract: `src/views/views.sql` ships one view. If a lesson
  teaches SQL against `uc_ai_agent_executions`, say whether that is stable.

### 2. Prove the tutorial is executable before you plan it

Do not plan live output you have not proven you can produce.

```bash
timeout 120 sql -name local-23ai-uc_ai <<'EOF'
set serveroutput on
-- smallest possible live call
EOF
```

Confirm, and write the numbers down for the plan:

- the DB connection works and UC AI is installed
- a **live provider call succeeds** (the docs promise real output; without a
  working key the whole recorded-output plan is fiction)
- **real latency**, per model. Readers ask "can I put this in a page process?"
  and the answer depends on this number. Measure it; do not estimate.
- the result JSON keys you will quote (`usage.prompt_tokens`,
  `usage.completion_tokens`, `final_message`)

### 3. Pick a use case against these tests

The scenario must pass all four:

- **One sentence.** If it needs two, it is too clever.
- **Real joins.** Several tables with a foreign-key story, so tools have to do
  actual work.
- **A rule the database owns.** Something the model must *ask* about and the
  DB *decides* (a return window, a credit limit, an approval threshold). This is
  the single best moment in a UC AI tutorial: the model proposes, PL/SQL refuses,
  and the refusal comes back as text the model can explain.
- **An authorization boundary.** A reason the run must be bound to one
  subject. This is what makes in-database AI look different from an API wrapper.

Note the audience bias: Oracle shops are **internal-systems** shops. A
consumer-webshop scenario demos well but a service desk / work order / AP
exception desk lands harder in review, because the compliance conversation is
smaller. Weigh demo value against "I could pilot this next week".

### 3b. Walk the reader's path for missing prerequisites

Read the lesson list in order and ask, per lesson: does this need an API,
parameter, object, or *status change* the reader has not been given yet? This is
where the worst defects hide, because each lesson is individually correct.

Two real examples, both caught only by walking the path:

- A run-context lesson placed before the agent lesson was **unbuildable**:
  `execute_profile` has no `p_run_context`, so run context only flows through
  `execute_agent`. The reader would have had to abandon the profile they had just
  built.
- `create_prompt_profile` and `create_agent` both default to `draft`, while
  resolution by null version selects `active`. A reader following the lesson
  literally gets `NO_DATA_FOUND` twice. Activation must be an explicit numbered
  step, never implied.

Also check the *inverse*: an object a lesson creates that silently changes earlier
lessons. A package named `UC_AI_HOOK` activates schema-wide by convention, so
compiling it in the last lesson retroactively routes every earlier agent — and
the test suite — through it. Anything like that belongs in the teardown script and
needs a warning where it is introduced.

### 4. Get adversarial review before planning — two reviewers, in parallel

Write the proposal to a scratch file, then spawn **two** sub-agents at once with
different jobs. One reviewer is not enough; they miss opposite things.

- **Codebase auditor** — verify every API claim against the specs, find
  redundancy with existing guides, check ordering, flag what ages badly. Tell it
  to cite `file:line`.
- **Target reader** — role-played as an experienced Oracle/APEX developer who
  has never used the framework. Ask where they drop off, what feels like filler,
  what questions go unanswered, whether setup friction is acceptable, and what
  single addition would make them show a colleague.

Demand a verdict (`APPROVE` / `APPROVE WITH CHANGES` / `REWORK`,
`WOULD FINISH` / `WOULD DROP OFF AT PAGE N`). Instruct both: **critical feedback,
not approval**, and write no files.

The reader reviewer is the one that changes the plan. It is where "cut the
feature tour", "you promised cost and store tokens", and "your security lesson
ships a data leak" come from. Take the drop-off page seriously: everything after
it is content nobody reads.

If a style reference is supplied mid-flight, send it to the running reviewers
with `SendMessage` rather than starting over. A completed agent resumes with its
context intact, so a follow-up question costs almost nothing.

**Iterate until the verdict flips.** Expect `REWORK` and "would drop off at page
N" on the first pass — that is the review working. Rework the plan, then send it
back to the *same* two agents for a second pass: they remember what they asked
for and will tell you whether you actually fixed it, which a fresh reviewer
cannot. Ask the second pass to re-walk the ordering specifically; the first pass
finding one fatal defect is no evidence there is not a second. Only plan the work
once both verdicts have turned (`APPROVE WITH CHANGES` and "would finish" is good
enough — the remaining items are edits, not restructuring).

Where the two reviewers disagree, decide rather than average, and hand genuinely
commercial or product-shaped choices to the user with a recommendation. In this
workflow that was the scenario domain, the lesson count, and where the free/paid
line falls — none of which a reviewer should settle.

**Verify any claim about model behaviour empirically before teaching it.** A
well-formed request is not a working pattern. Structured output combined with tool
calling *sends* correctly, but nothing in the codebase asserts what the model does
under forced strict JSON plus tools — a strict schema can pull it into answering
immediately instead of calling a tool first. Run it on the dev DB and read the
trace before a lesson depends on it. If it turns out flaky, the honest lesson
("here is the interaction, here is how to make it reliable") is better content
than the happy path.

### 5. Shape the series from the feedback

What the reviews converged on, and what to reuse as defaults:

- **6 lessons of 20-25 minutes beats 11 of 15.** "Lesson 1 of 11" reads as a
  three-hour commitment and the tab closes. Over 8 lessons, split into two named
  courses so each progress indicator stays short.
- **Never teach the insecure version first.** If lesson N+1 fixes a security
  hole that lesson N created, search engines will land readers on lesson N and
  they will copy it. Make the tools context-bound from birth; keep the attack
  demo as *proof*, not as *repair*.
- **Prove security deterministically.** "Ask for another customer's order and
  watch it refuse" proves the *model* declined. Call the handler directly with a
  forged id and show it still returns only the bound subject's rows.
- **Put the debugging lesson early** (before the halfway point). The reader
  needs it at lesson 3, not lesson 9.
- **Debugging and the trace tables are the same lesson.** UC AI already records
  a full normalized trace, so do not invent a debugging technique — teach the
  audit trail and debugging comes free. `uc_ai_agent_messages` holds one row per
  content item (`role` in user / assistant / tool_call / tool_result /
  reasoning / system, with `tool_name`, `tool_input`, `tool_output`,
  `tool_status`, ordered by `seq`), and `uc_ai_agent_executions` records the
  `run_context` and `env_context` in force plus the APEX user, session, page,
  host, and ip. "The model called no tool" is then a `select`, not a mystery.
  Split it across two lessons: the **trace** early (reading one run to see what
  the agent did and why), and **audit / governance** late (who ran what, token
  totals per session, `feedback_rating`, hooks). Check which of this the
  reference guides already own — as of writing these tables are mentioned in
  passing by the multi-agent pages but no page teaches them, so it is new
  content and worth a lesson of its own.
- **Motivate before mechanics.** Let the reader feel the pain before the fix —
  hard-code a prompt in three places, *then* introduce prompt profiles. This
  usually means tools come before prompt profiles, not after.
- **Cut the "going further" page.** A page of teasers for features you did not
  teach is a link farm, and every item already has a guide. End on the payoff
  and put "what to read next" in a box.
- **No paywall inside a learning path.** Teach the free capability; mention the
  paid tier in one sentence outside the lessons.

### 6. Write each lesson to one fixed skeleton

Style: Anthropic Academy framing, reference-grade code density. The framing wins
attention; the density is what an Oracle developer actually uses at work with
SQL Developer on the second monitor.

Per lesson, in this order every time — predictable beats elegant, because the
reader learns where to skip to:

1. **Title**, then one promise line: "By the end, your agent can file a return
   request and refuse one that is out of window." Not an objectives block.
2. **`Lesson N of M · ~20 min`** on its own line.
3. **The problem, first.** What breaks without this lesson's capability. Use the
   "Without X … With X" contrast; it is the strongest device in the format.
4. **The code that IS the lesson.** At most **3 inline blocks, none over ~40
   lines**. If a handler body runs 90 lines, inline the 12 that make the point.
5. **"What changed"** — a short prose or bulleted read of the block.
6. **A verification section, in two parts** (this is the highest-trust element
   of the whole series):
   - the **real recorded output**, verbatim, stamped with model and date, plus
     "your wording will differ — the tool-call sequence is what must match"
   - a **deterministic check the reader runs themselves**:
     `select rma_number, status from uc_demo_returns where ...`. With an LLM the
     reader cannot tell "wrong" from "differently phrased"; a SQL assertion they
     can.
7. **Key Takeaways** — exactly 3 bullets, and make one of them a line of code.
8. **Full reference** link to the relevant guide (this is how lessons stay short
   without losing the reader), then one **`LinkCard`**: "Next lesson: …".

Starlight components available in this repo: `Aside`, `Steps`, `Card`,
`CardGrid`, `LinkCard` (see usage counts with a grep over
`docs/src/content/docs/`). There is no reading-time or progress component —
write the `Lesson N of M · ~20 min` line as plain text.

### Layout for more than one course

```
docs/src/content/docs/tutorial/index.mdx                 lists ALL tutorials
docs/src/content/docs/tutorial/<course-name>/01-....mdx  the lessons
```

The sidebar carries **one entry for everything**:

```js
{ label: "Tutorials", items: ["tutorial"] }
```

Each card on that index links **straight to lesson 1**. A new tutorial is then a
new directory plus a card — no config change at all.

Two mistakes to avoid, both made in this workflow:

- **Nine lessons as nine sidebar items.** It becomes the heaviest group in the
  menu and buries every other section. The lessons belong on a page, not in the
  nav.
- **A per-course overview page between the index and lesson 1.** This seems
  reasonable and is redundant: lesson 1 already opens with what you build, the
  prerequisites and the setup, so an overview repeats it and adds a click before
  the reader can start. The user's words: *"the index page just repeats chapter
  1"*. One index listing the tutorials, then straight into lesson 1.

What the tutorials index SHOULD hold: what each tutorial builds, how many lessons
and how long, and what it teaches that no guide covers. What it must NOT hold:
prerequisites, setup, cost, or which model was used — those live in lesson 1,
where the reader needs them.

Never `autogenerate` a course directory: it sorts an index in with the lessons and
loses the order.

Two things to get right when moving lessons into a subdirectory:

- **Component import depth** changes (`../../../components/` becomes
  `../../../../components/`). The build catches this.
- **Every cross-link and `LinkCard` href** gains the course segment. A dead link
  fails the build, but a link resolving to a leftover *old* copy passes — so move
  with `git mv`.

**A stale sidebar slug is the error you will see first**: "the slug … specified in
the Starlight sidebar config does not exist". It means the config still names a
pre-move path, so update the config in the same commit as the move. If the config
is already correct and the error persists, it is the **dev server cache** —
restart it. `bun run build` is the honest check.


### 7. Setup and teardown: remove all friction

The reader will abandon on setup before they ever judge the content.

- **One** idempotent script that drops-if-exists, creates, seeds, and ends with a
  verification `select` printing expected row counts ("setup OK: 4 customers,
  6 orders, 1 backordered item").
- **One** teardown script, offered in the same box. The reader has to promise a
  DBA they can remove it.
- Prefix all demo objects (`uc_demo_`).
- Inline the block that is the lesson *and* ship the full scripts for download.
  Repo to reproduce, page to understand — both, not either.
- State the minimum DB version for the tutorial, and which lessons need more.
- Never require a second setup (such as the sample APEX app) to finish.

### 8. Be honest on page 0

Cheap to write, and it buys trust from exactly the cautious reader you want:

- **The network ACL / TLS wallet step needs a DBA.** Say it takes ~20 minutes,
  say to do it first, and show the error you get when the certificate is
  missing. This is where real projects stall for a week.
- **Data leaves the database.** UC AI markets "everything runs in your database";
  a tutorial that sends customer names to a provider must say so once, plainly.
  Add the escape hatch: which constants to change for Ollama or OCI, and which
  lessons work without a paid key.
- **What it costs.** One number: "recording the whole series took ~N runs, about
  $X". Ship a small price table plus the join that turns stored tokens into
  money, since UC AI stores tokens only.
- **Which model.** Name the model the recorded runs used, and note per lesson
  when a weaker one needs better tool descriptions.

### 9. Test plan: every lesson gets both kinds of test

Plan these *with* the lessons, because the recorded output is the deliverable.

- **Deterministic, in utPLSQL** (`test_uc_ai_tutorial`): tool handler results,
  run-context isolation with a forged id, the business rule's refusal path,
  memory store resolution, placeholder-validation errors. Assert on **tool calls
  and rows**, never on answer text.
- **Failure paths**, because the debugging lesson is written from them: the model
  calls no tool, the model exceeds `g_max_tool_calls`, the HTTP call dies
  mid-run leaving a written row. Without these tests the debugging lesson has no
  source material.
- **One recorded live run per lesson**, captured verbatim into the page: final
  message, tool-call sequence, token counts, and the rows the write tool
  produced.
- Also give the reader the reader-facing version: how to regression-test *their*
  agent in CI without burning tokens. This must land **on a page**, not only in
  the internal test plan — otherwise the question is not answered for the reader.
  Note that `uc_ai.set_exec_context` is marked "not intended for user code", so it
  belongs in the test package only, never in a lesson.

Assertion quality, which is where these tests usually fail:

- **Count rows; never match a substring.** "The answer contains the credit-note
  number now in the table" passes when the write tool fired *twice*, and passes
  when the model invented a number that happens to match. Assert exactly one new
  row attributable to the run, *and* that its key appears in the answer.
- **Test every conjunct of a business rule, including an accept path.** A rule
  with four conditions needs four refusals and at least one acceptance —
  otherwise a check stubbed to always-refuse stays green. Test boundaries on both
  sides (exactly at the limit must pass; one unit over must refuse).
- **Derive boundary dates from the same expression the seed uses.** Relative seed
  dates (`sysdate - 20`) only survive publication if the tests compute their
  boundaries the same way; a literal in the test throws the benefit away.
- **A shared dev database can invalidate a recording while you make it.** If other
  sessions are recompiling framework packages, output you captured minutes ago may
  describe behaviour that no longer exists. This happened twice in one session: a
  memory lesson recorded a failure that a peer had already fixed, and then recorded
  the *fixed* behaviour reverting because the package was recompiled mid-run. Before
  trusting any captured transcript, re-test the specific behaviour it depends on
  with a one-line direct call, and re-record if it differs. `last_ddl_time` on the
  package tells you whether it moved under you.

**Reset to lesson N's state before recording lesson N — and mean all of it.** This
is the single most repeated mistake in this workflow: three separate bad recordings
came from a database that was ahead of the lesson being written. Data is the easy
part. What also has to be reset:

- **Configuration the framework stores**, not just rows you seeded. A prompt
  profile's model configuration, response schema, and version; the agent's status;
  tool rows a later lesson registers; memory configuration.
- **A later lesson's changes to an earlier lesson's object.** The worst case is
  self-inflicted: lesson 7 added a response schema to the shared profile, which
  turned `final_message` into an object, which made lesson 6's `get_clob` print
  empty. The lesson-6 script was correct; the database was living in lesson 7.
- **Anything a probe left behind.** A memory config row from an experiment made a
  lesson-2 call raise an error a reader would never see.

A reader at lesson N has run scripts `00..N` and nothing else. If reproducing that
takes more than one command, write the reset as a script — the cost of getting it
wrong is a published page that is confidently false.
- **Assert the trace exists**, since it is the artifact of the debugging lesson:
  rows with `role in ('tool_call','tool_result')` and non-null `tool_name`. Assert
  the role set and tool names, never the content.
- **Make the drift job bite.** "Reports diffs without failing the build" means
  nobody looks. Split it: **fail** on structural drift (tool-call set, row counts,
  `finish_reason`, schema validation), **report only** on prose drift.
- Test teardown-then-setup, not just setup twice.
- Isolate anything that resolves by convention (see step 3b) inside the test that
  creates it, or it changes every other suite in the schema.

### 10. Language and linting

- Invoke the `simple-english` skill before writing or editing any page under
  `docs/src/content/docs/`. Keep CLAUDE.md's fixed terminology ("make sure
  that", "configuration", "call", "run", "delete", "error", "failure").
- Never change an existing heading: `starlightLinksValidator` fails the build on
  anchors other pages link to.
- **Only Markdown headings (`##`, `###`) produce anchors.** Asides, tables,
  `<Steps>`, `<Card>` and code blocks do not. **An `<Aside>` never emits an `id`,
  with or without a `title`** — it renders as
  `<aside aria-label="..." class="starlight-aside starlight-aside--caution">`.
  That makes a titled Aside the trap: the title is visible, looks like a
  heading, and is not addressable. Verified in the built HTML, not assumed.
  Since a tutorial links out constantly, confirm every target id before writing
  the link:

  ```bash
  # what a page actually exposes, from the build output
  grep -o 'id="[a-z0-9_-]*"' dist/guides/<page>/index.html | sort -u
  ```

  If the thing you want to point at has no heading, ask whoever owns that page to
  add one above it rather than guessing an id from the visible text. A guessed
  anchor fails the build and reads as your bug, not as a missing anchor.
- Lint every SQL or PL/SQL file the series ships:
  `dblinter check <paths>`, then read `./.dblinter/check.sarif.sarif` and fix
  each finding. Suppress only with a written reason.
- Build the site before finishing: `cd docs && bun run build`. The links
  validator catches every broken cross-reference between lessons.
- **A forward link breaks the shared build immediately.** `starlightLinksValidator`
  fails the whole build on a link to a page that does not exist yet, and it scans
  every page whether or not the sidebar references it. So a lesson 1 that ends
  with "Next lesson: …" pointing at an unwritten lesson 2 turns the build red for
  every other session in the repo, not just for you. Three ways to avoid it, in
  order of preference:
  1. Write the lessons in order and add each "Next lesson" link only once its
     target file exists.
  2. Create all lesson files as stubs first, so every forward link resolves from
     the start.
  3. Write the next-lesson pointer as plain text, and convert it to a `LinkCard`
     when the target lands.

  Run `bun run build` after **every** page, not once at the end — the cost of
  finding out late is paid by whoever else is working in the repo.

## Anti-patterns

Each of these was caught in review of a real plan:

- **A vendor goal in the plan.** "Show how much the product can do" inflates the
  page count and produces a feature tour. Let the scenario decide the lessons.
- **"Production-shaped"** with no error handling, retry, rate limiting, PII
  discussion, rollback story, or latency numbers. Call it demo-shaped, or earn
  the word.
- **A strawman lesson 1** built only so later lessons can knock it down. Show a
  *real* failure instead: ask about another subject's data and watch the model
  confidently invent an answer.
- **Promising a word the schema cannot back** ("cost" when only tokens exist).
- **A too-polished opening transcript.** If the sample output looks perfect the
  reader assumes it is fabricated and trusts nothing after it. Paste the real
  one.
- **A third dataset.** The docs already carry a time-tracking dataset and a
  sample app. Adding another world the reader must learn has a cost — consider
  making the tutorial's dataset the site's dataset over time, and at minimum say
  on page 0 how it relates to the others.
- **Collapsing conditional behaviour into an unconditional warning.** Getting a
  caution *directionally* right is not enough; an over-correction misleads too.
  A real example from this workflow: "memory `user` scope keys on the DB user" —
  it actually keys on `coalesce(apex_user, db_user)`, so it isolates correctly for
  an authenticated APEX caller and only collapses to one store for a public app,
  ORDS, or a job. The sloppy version reads as "this feature is broken" and would
  push a reader off a scope that is right for them. When a behaviour depends on
  the caller's context, enumerate the cases in a small table, and check the
  mechanism in the body before writing the warning — not just the symptom you
  happened to hit.
- **Restating a reference caution instead of linking it.** When another page owns
  the detail, link its heading. The tutorial's copy is the one that goes stale,
  and heading text is load-bearing: `starlightLinksValidator` fails the build on
  a moved anchor, so agree with whoever owns that page to keep it stable.
