# AgentFlow, third iteration: less on screen, honest loop, no dead air

Reviewed at commit `9d9fd87` (working tree clean apart from the two earlier
review notes). Read every file under `AgentFlow/`, recomputed the timeline from
the constants in `story.ts`, and measured scene 6 in the browser at 1440 px.

Three questions from you, in order of what I found:

1. **Is the workflow right?** Not quite. The picture shows four model calls
   where a real UC AI run makes seven, and it drops exactly the ones that
   would fill the two gaps you noticed. Section 1.
2. **The break after `get_payments`, and the wait before the answer.** Both
   are dead tails. Across the run, 46 of the 88 seconds are time after the
   last visible change in a scene. Section 2 has the per-scene numbers.
3. **Too crowded.** Yes, and not because the text is big. Scene 6 has 35 text
   items in 12 different rendered sizes in one frame. The fix is fewer things,
   not smaller things. Your idea, tables and tools only when the camera is on
   their agent, is the right one and generalises. Section 3.

---

## 1. The workflow: what a real run does versus what the picture shows

In UC AI an orchestrator agent is a model loop whose tools are sub-agents, and
each sub-agent is a model loop whose tools are your functions. One request in
this story makes these model calls:

| # | Who calls the model | With what | The model returns |
|---|---------------------|-----------|-------------------|
| 1 | Orchestrator | the user's question | call Billing agent |
| 2 | Billing | the task | call `get_payments('INV-1003')` |
| 3 | Billing | the rows from `get_payments` | "two payments of €49, a duplicate" |
| 4 | Orchestrator | Billing's answer | call Policy agent |
| 5 | Policy | the task | call `find_policy('duplicate_payment')` |
| 6 | Policy | the row from `find_policy` | "refund the extra payment" |
| 7 | Orchestrator | Policy's answer | the final answer |

Seven model calls, two tool calls, three agents. The animation shows calls 1,
2, 4 and 7. It skips 3, 5 and 6.

**The break after `get_payments` is call 3.** Scene 6 ends with the rows in
the table and the "2 rows → JSON" chip fading, then holds 4.4 seconds. In a
real run that is the moment Billing sends the rows to the model and gets
"two payments, a duplicate" back. The visitor's intuition that a model call
is missing here is correct. The hold then makes the gap look like a bug.

**Policy's tool choice is not a model call at all.** `find_policy` lights up
"when the orchestrator's delegation reaches the Policy agent"
(`CHOSEN_AT.find_policy`). That contradicts scene 5's own caption: "The model
does not run code. It picks one of your functions." For Policy, nobody picks.

**The session strip then says "4 model calls".** Once the loop is honest the
strip has to say 7, and it becomes a stronger closing line: seven model calls,
two function calls, one session id.

### Show every model call, but make a model call cheap

Today a model call costs 4.5 seconds: a chip out (0.85 s travel, 0.9 s rest,
0.4 s fade), a wait, a chip back. Seven of those would be 31 seconds. So
change the mechanism rather than the count.

**A model call is a beat, not a trip.** When an agent consults the model:

- the wire from that agent to the model box lights for the duration;
- the model box shows its thinking dots and a one-line note of what it was
  given ("the rows", "the task", "the question");
- when it ends, the agent card gets the result as persistent state: the tool
  row lights and opens, or the plan ticks, or a one-line note appears under
  the agent title ("2 payments · €49 · a duplicate").

No chip leaves the agent. Nothing travels. A beat is about 1.1 seconds, and
it can happen inside a scene between two chips. The rhythm the visitor sees
is then *think, act, think, act*, which is exactly the mental model of an
agent loop.

Chips stay for the things that really move between places: a task to a
sub-agent, a result back to the orchestrator, a call into a table and rows
back, the answer to the user.

Add the missing wire `policy → model`.

### A "beat" in the data

```ts
export interface Beat {
  /** The agent that consults the model. */
  agent: string;
  /** Milliseconds after the camera arrives. */
  at: number;
  /** Shown on the model card while it thinks. */
  given: string;
  /** Written onto the agent card when the beat ends. */
  yields?: string;
}

interface Scene {
  …
  beats: Beat[];
}

export const BEAT_MS = 1100;
```

Rendering: `thinking` in `AgentFlow.tsx` becomes "any beat whose window
contains `motion`"; `Wires` receives the set of lit wires rather than lit
nodes; `Agent` and `Orchestrator` render `yields` of every beat already
reached (section 4 has the helper).

---

## 2. Timing: where the 88 seconds go

Recomputed from `CAMERA_MS`, `TRAVEL_MS`, `LINGER_MS`, `FADE_MS`,
`CHIP_GRID_MS`, `REVEAL_STAGGER_MS` and each scene's `hold`. "Last change" is
the last moment a reader sees something new (a chip land, a row appear, the
second camera arrive). "Dead tail" is the time from there to the scene's end.

| Scene | Last change (ms into motion) | Scene length | Dead tail |
|-------|------------------------------|--------------|-----------|
| 1 The system | 1 540 | 6.0 s | 3.6 s |
| 2 The request | 850 | 6.1 s | 4.3 s |
| 3 The plan | 3 100 | 8.5 s | 4.5 s |
| 4 Delegate | 850 | 6.1 s | 4.3 s |
| 5 Choose a tool | 3 100 | 8.9 s | 4.9 s |
| 6 Read your data | 3 100 | 9.7 s | 5.7 s |
| 7 Report back | 5 350 | 10.8 s | 4.5 s |
| 8 Second specialist | 5 350 | 12.0 s | 5.7 s |
| 9 Combine | 5 350 | 10.8 s | 4.5 s |
| 10 The answer | 4 400 | 9.5 s | 4.2 s |
| **Total** | | **88.2 s** | **46.2 s** |

Every scene holds 3 to 4.4 seconds *after* its last chip has already rested
0.9 s and faded 0.4 s. The commit message calls this reading time, but there
is nothing new to read: the chip is gone and the card state has been visible
for seconds.

**Rule: a hold is for reading what just changed.** If the last event of a
scene reveals content (SQL card, rows, the answer bubble), hold long enough to
read it, about 2.5 to 3.5 s. If the last event is a chip that has already
faded, hold 0.5 s and move on. Under that rule the same content runs in about
50 seconds. Section 5 has the budget.

### The wait before the answer, in detail

Scene 9 "Combine" ends with a decision chip "Answer ready" that lands, rests,
fades, and is followed by 3.2 s of nothing. Scene 10 then starts with a 0.9 s
camera move, and during that move two things happen at once:

- the You card grows by 140 units (`collapsedH` 330 → `h` 470, with a 400 ms
  height transition) and the answer bubble pops in immediately, because
  `answerVisibleAt(index)` only looks at the scene index;
- a *second* "Answer ready" chip leaves the orchestrator and arrives 0.85 s
  later at a card that already shows the answer.

So the visitor sees: "Answer ready" … silence … camera pans while the answer
appears … "Answer ready" again, arriving after the fact. Three faults:

1. The decision chip at the end of scene 9 says nothing the next scene does
   not say better. Delete it; end scene 9 on the model beat (section 1), with
   `yields: "Answer ready"` on the orchestrator card, and a 0.5 s hold.
2. The answer must appear when the chip lands, not when the scene starts.
   This is the same fault that was fixed for `get_payments` in `9d9fd87`
   (`CHOSEN_AT` with `afterMs`), and it exists for every other index-only
   predicate: `answerVisibleAt`, `planAt` (ticks appear at the start of
   scene 7 while "2 payments" is still travelling), `planNoteAt` ("A
   duplicate. Ask Policy" is on the card at the start of scene 7, before the
   model was asked "What next?"), `summaryVisibleAt`. Section 4 fixes them
   together.
3. The You card should not resize during a camera move. Grow it when the
   chip lands, in the same frame the bubble appears. Then the camera for
   scene 10 is computed with the grown height from the start (it already is:
   `rectsFor(frame, index)`), and the visitor sees one motion, not two.

---

## 3. Density

### Measured, scene 6 at 1440 px (viewport 775 × 436, scale 0.775)

- 35 visible text items, 50 words, inside one frame.
- 12 distinct rendered sizes: 20.2, 15.5, 14.7, 14.0, 13.2, 12.4, 11.6 px
  and their variants.
- Five cards in frame: Orchestrator (cut, dim), Billing (lit), PAYMENTS
  (lit), Policy agent (dim), REFUND_POLICIES (dim, cut). The scene is about
  two of them.
- Inside Billing alone: title, subtitle, three tool rows each with a glyph
  and a name, a "PL/SQL function" tag, four lines of SQL. Inside PAYMENTS: a
  "table" label, a title, a three-column header, nine cells.

**Is the text too big?** No. Titles render at 20 px and body text at 12 to
15 px on a desktop, which is normal reading size; the far view already has
its own larger sizes. Making the text smaller would add room and remove
legibility at the same time. The problem is the count: 35 items where a
frame can carry about 10 to 12, and 12 sizes where a design system has 3.

### Idea A. Semantic zoom: detail exists only where the camera is

This is your suggestion, generalised. A map shows streets only when you zoom
in. The canvas should do the same.

Two levels of detail:

- **Level 0, the system.** You, Orchestrator, Billing agent, Policy agent,
  the model box, the boundary, and (at the end) the session strip. Agent
  cards are compact: icon and title, one line. No tools, no tables, no
  subtitles. This is what scenes 1, 2, 3, 6 (orchestrator turns) and the
  closing pull-out show.
- **Level 1, inside one agent.** When a scene is about an agent's turn, that
  agent's card opens (height transition, like the You card does today), its
  tool rows appear inside it, and its table fades in beside it with the
  wire. Only that agent. The other agent stays a compact level-0 card.

Data: give agents `compact: { w, h }` and give tools and tables
`detailOf: "billing" | "policy"`. A scene declares `detail?: "billing" |
"policy"`. `rectsFor` returns the open rect for the detailed agent and the
compact rect for the others; nodes with `detailOf` render only when their
agent is the scene's `detail` (fade 300 ms in, none out, since the camera has
moved on by then). Wires to a table exist only while its agent is detailed.

Effect on scene 6: the frame holds Billing (open) and PAYMENTS, with Policy
as a small compact card at the edge and nothing inside it. Item count falls
from 35 to about 16 before any other change.

Effect on the far view: the overview becomes five titled boxes and a model
box. That is what a block diagram of a multi-agent system should look like,
and it removes every `is-far` hide rule for tools and rows, because they no
longer exist at level 0.

### Idea B. Three text sizes, and every word earns its place

Set exactly three sizes on the canvas: title 26, body 18, code 16. Delete the
rest (subtitles 18 stay body, tags 17 go, table header 15 goes to code 16,
`ƒ` glyph 20 goes).

Then cut words:

- **Subtitles.** "Plans the run", "Finds the payment facts", "Finds the refund
  rule", "APEX · PL/SQL": delete. The titles say it. Keep the model's
  subtitle, shortened to "any provider", and swap it for the beat's `given`
  text while it thinks.
- **Tool row.** Name only. Drop the `ƒ` glyph or the tag; the open SQL card
  is what says "function". Keep the tag on the open card only.
- **SQL card.** Two lines with the bind substituted, so the reader does not
  have to join a bind name to a value:

  ```
  select amount, status from payments
  where  invoice_id = 'INV-1003'
  ```

  Real syntax is kept; the caption can still say "with a bind variable" if
  you want the point made.
- **Table.** Two columns. PAYMENTS: `INVOICE_ID`, `AMOUNT`. Drop `STATUS`; it
  adds three cells and no meaning. Drop the "table" word; the icon and the
  uppercase name say it. REFUND_POLICIES is already two columns.
- **Plan card.** Keep the two checkbox lines. Delete `af-plan-note`. What the
  model decided is now the beat's `yields` line, one line, replacing itself
  each time, and the caption narrates it.
- **Chips.** Four words or fewer. "Check the payments for INV-1003" →
  "Check payments · INV-1003". "reason_code = 'duplicate_payment'" →
  "duplicate_payment". "Find the refund rule" → "Find refund rule".
- **Captions.** Twelve words or fewer. Several current captions restate the
  chip that is on screen at the same moment.

### Idea C. One frame, one new thing

Each scene introduces exactly one new object (a card opening, a table, the
answer) and one motion at a time. Scene 6 today introduces the SQL card, the
table header, three rows, a task chip and a result chip. Split the
introductions across the beat structure in section 5, or accept that some
scenes have two, but never five.

### Idea D. Frame the subject, not the neighbourhood

With level-0 compact cards the neighbours shrink, but they are still dimmed
boxes in the frame. Two small changes help: raise `framePadding` from 70 to
about 110 so the subject has air and the dimmed neighbours sit nearer the
edge, and lay the canvas out so that an agent's table is beside it and the
other agent is *below* the frame line of a 16:9 crop (Policy at `y ≥ 560`
already nearly does this; with a compact 110-unit card it will).

### What not to do

- Do not shrink the canvas text. See above.
- Do not remove the SQL card or the table; they are the point of the
  animation. Make them the only detailed things in their frame.
- Do not hide the model box in the agent scenes. Its beat is what makes the
  loop visible.

---

## 4. One helper for every landing state

Every "from when is this visible" predicate should take the scene clock, not
just the scene index. Today `toolChosenAt` does and the others do not, which
is the root of the pre-empted answer, plan ticks and plan notes.

```ts
/** A moment in the run: a scene and milliseconds after its camera arrives. */
export interface Moment { scene: number; at: number }

export function reached(m: Moment, index: number, motion: number): boolean {
  return index > m.scene || (index === m.scene && motion >= m.at);
}
```

Then, in `story.ts`, name the moments instead of scattering constants:

```ts
export const MOMENTS = {
  planShown:    { scene: 2, at: BEAT_END(0) },
  planTick1:    { scene: 4, at: RESULT_LANDS },     // when "2 payments" lands on the orchestrator
  planTick2:    { scene: 6, at: RESULT_LANDS },
  billingOpen:  { scene: 3, at: 0 },
  getPayments:  { scene: 3, at: BEAT_END(0) },
  paymentsRows: { scene: 4, at: TRAVEL_MS },
  policyOpen:   { scene: 5, at: 0 },
  findPolicy:   { scene: 5, at: BEAT_END(0) },
  answer:       { scene: 7, at: TRAVEL_MS },        // when the answer chip lands
  summary:      { scene: 7, at: FRAME_THEN_AT + CAMERA_MS },
};
```

`Nodes.tsx` receives `motion` for every node kind (drop the `CLOCKED` set) and
asks `reached(MOMENTS.x, index, motion)`. Manual stepping passes
`motion = Infinity` through `settled`, so every end state is still exact.

This also lets the You card grow at `MOMENTS.answer` rather than at scene
start, and lets the Summary counters start at `MOMENTS.summary`.

---

## 5. A budget that runs in about 50 seconds

Constants: camera 800, travel 700, chip rest 500, chip fade 300, beat 1 100,
row stagger 160. Holds follow the rule in section 2. Eight scenes; the
orchestrator's turns are their own scenes so the loop is visible, and Policy
is one compressed scene because the visitor has seen the pattern once.

| # | Scene | Camera | What happens, in order | Hold | ≈ Length |
|---|-------|--------|------------------------|------|----------|
| 1 | The system | whole canvas, level 0 | nodes reveal, wires draw | 2.5 s | 4.5 s |
| 2 | The request | You + Orchestrator | chip You → Orchestrator | 1.2 s | 3.7 s |
| 3 | Orchestrator thinks | Orchestrator + model | beat (given: "the question", yields: "Ask Billing first"); plan card appears; chip Orchestrator → Billing | 0.8 s | 4.6 s |
| 4 | Billing picks a tool | Billing (opens) + model | beat (given: "the task"); `get_payments` lights and opens with its SQL | 3.0 s to read the SQL | 5.6 s |
| 5 | Your function runs | Billing + PAYMENTS (appears) | chip tool → table; rows; chip "2 rows" back; beat (given: "the rows", yields: "2 × €49 · duplicate"); chip Billing → Orchestrator; plan ticks | 1.2 s | 8.3 s |
| 6 | Orchestrator thinks | Orchestrator + model | beat (given: "Billing's answer", yields: "Ask Policy"); chip Orchestrator → Policy | 0.8 s | 4.2 s |
| 7 | Policy, the same again | Policy (opens) + REFUND_POLICIES | beat; `find_policy` opens; chip to table; 1 row; chip back; beat (yields: "Refund the extra payment"); chip Policy → Orchestrator; plan ticks | 1.5 s | 8.4 s |
| 8 | The answer | Orchestrator + model, then You, then whole canvas | beat (given: "both answers", yields: "Answer ready"); chip Orchestrator → You; You grows and the answer pops on landing; hold 3 s; pull out; summary counts up: 7 model calls · 2 function calls · 3 agents · 1 session | 3.0 s | 11.5 s |
| | | | | **Total** | **≈ 51 s** |

Captions, twelve words or fewer, one per scene:

1. Everything here runs in your Oracle database. Except the model.
2. A customer asks one question.
3. The orchestrator asks the model what to do first.
4. Billing asks the model which of your functions to call.
5. UC AI runs get_payments. Your SQL, your table. The model reads the rows.
6. The orchestrator asks the model what is next.
7. Policy does the same with find_policy.
8. One answer, seven model calls, two of your functions, one session.

Scene 5 is the longest single scene and carries the most. If it feels heavy
in the browser, split it after "2 rows" lands: 5a "Your function runs", 5b
"Billing reports back". That adds one camera move and about 1.5 s.

---

## 6. Order

1. **Beats and honest model calls.** Add `Beat`, the `policy → model` wire,
   render beats as wire glow plus model dots plus a `yields` line on the
   agent. Convert every model round trip to a beat. Session strip to 7.
   Section 1.
2. **`reached()` and `MOMENTS`.** Replace every index-only predicate.
   Answer bubble and You growth on chip landing. Delete the second "Answer
   ready" chip. Section 4 and 2.
3. **Holds by the rule.** Rewrite `hold` per scene from the table in
   section 5. Check the total in the console with `TOTAL_MS`. Section 2.
4. **Semantic zoom.** `compact` rects, `detailOf`, scene `detail`, tables and
   tools rendered only when their agent is detailed, `is-far` rules pruned.
   Section 3, idea A.
5. **Words and sizes.** Three sizes, subtitles gone, two-line SQL, two-column
   tables, plan note gone, short chips and captions. Section 3, ideas B
   and C.
6. **Framing.** Padding 110, Policy below the 16:9 crop of Billing scenes.
   Section 3, idea D.

After each step: watch one full autoplay without touching anything and note
every moment you wait for something that does not come. That is the test the
two questions in this round came from, and it is the right one.

---

## 7. What I did not verify

- I did not watch the current run end to end in real time; the timeline is
  computed from the constants, and the constants are the truth for this
  component, but a browser under load can stretch a scene.
- I did not measure the phone view in this round. Nothing in this iteration
  makes it worse; semantic zoom makes it better, because a phone frame then
  holds one compact card instead of one card and its neighbours.
