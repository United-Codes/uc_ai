# AgentFlow redesign guide

The homepage animation (`AgentFlow.tsx`, `AgentFlow.css`, `AgentFlow/story.ts`)
follows one refund request through an orchestrator and two specialist agents.
It works, but it does not sell the idea. This document explains what is wrong
with the current version, what the next version should feel like, and how to
build it. Read it top to bottom before you touch the code.

Goal of the animation, unchanged: a visitor who knows nothing about agents
understands in 40 seconds that (1) a multi-agent system splits one question
between specialists, (2) each specialist calls the visitor's own PL/SQL
functions against their own tables, and (3) UC AI runs all of this inside the
Oracle database.

---

## 1. What is wrong today

Observed at 1440x1000 in dark mode on the local dev server. The content column
in Starlight is 720 px wide, so the stage is 720 x 603 px.

1. **The idle frame is mostly empty.** Before the visitor clicks "Follow the
   request", roughly 70 % of the frame is a dashed rectangle with a sentence
   in it. The specialist area is reserved up front so that nothing jumps
   later. That was the right trade-off for a static layout and the wrong one
   for a hero element. The first impression is a blank panel.

2. **Everything is the same size all the time.** Focus is expressed only with a
   border color and a soft background tint. The chat bubble, the orchestrator,
   the two specialists and the tool cards all sit at the same scale in the
   same gray. Nothing tells the eye where to look.

3. **The interesting parts are tiny.** The payment table, which is the moment
   where "your PL/SQL function reads your own rows" becomes concrete, is
   rendered at 0.72 rem inside a 230 px wide card. The travelling chip is a
   0.74 rem pill that moves about 200 px.

4. **Motion is 10 % of the time.** Each scene holds 4 to 5 seconds. The only
   motion in a scene is a 520 ms straight-line slide of one chip. For the
   remaining 3.5 to 4.5 seconds the frame is a still image.

5. **The value of UC AI is not visible.** "UC AI · Oracle Database" is a small
   label on a dashed box. There is no picture of the database boundary, no
   picture of data, and no picture of the model being called. A visitor cannot
   see that the model decides and PL/SQL executes, nor that data never leaves.

6. **The specialists look like they have one hard-wired step each.** Each agent
   shows exactly one tool, and it always runs. The core idea of function
   calling, that the model *chooses* among several of your functions, is
   absent. The user wants to see tools that exist but are *not* used in this
   run.

7. **The caption is outside the picture.** Narration sits below the frame. The
   eye travels between the visual and the text on every scene.

8. **Small defects.** At the last scene there are two "Replay" buttons (the
   primary button and a secondary one). `story.ts` exports `ANSWER_SCENE`
   which nothing uses. `AgentFlow.css` declares `:root[data-theme="light"] .af`
   twice.

---

## 2. Target experience

Think Canva or Prezi presentation mode: one large canvas that holds the whole
system, and a camera that zooms and pans to the part of the canvas the current
scene is about. Zoomed out, the visitor sees the whole shape of a multi-agent
system. Zoomed in, a single agent with its tools fills the frame and can carry
readable detail.

### 2.1 The canvas

One fixed-size logical canvas, 1600 x 900 units. Every node has a fixed
position on it. Suggested layout, left to right:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         ☁ AI model  (outside the database)                  │
│                      Claude · GPT · Gemini · Ollama (local)                  │
├──────────────────────────────────────────────────────────────────────────────┤
│  ORACLE DATABASE · UC AI                                                     │
│                                                                              │
│   You            Orchestrator          Billing agent        PAYMENTS   ▤     │
│   ┌────┐         ┌──────────┐          ┌─────────────┐      ┌────────┐       │
│   │chat│ ──────▶ │ plan     │ ───────▶ │ tools:      │ ───▶ │ rows   │       │
│   │    │ ◀────── │ ☐ ☐      │ ◀─────── │ get_payments│ ◀─── │        │       │
│   └────┘         └──────────┘          │ get_invoice │      └────────┘       │
│                       │                │ issue_refund│                       │
│                       │                └─────────────┘                       │
│                       │                Policy agent         REFUND_POLICIES  │
│                       └──────────────▶ ┌─────────────┐      ┌────────┐       │
│                                        │ find_policy │ ───▶ │ text   │       │
│                                        │ cust_tier   │      └────────┘       │
│                                        └─────────────┘                       │
└──────────────────────────────────────────────────────────────────────────────┘
```

Three things are new compared with today:

- **A database boundary.** A big rounded rectangle labelled "Oracle Database"
  contains You, the orchestrator, the agents, the tools and the tables. Only
  the AI model box sits outside it. Requests go out to the model and come
  back; data stays inside. This single picture is the pitch.
- **A model box.** Every time an agent "thinks", a small chip travels to the
  model box and comes back with a decision. The visitor learns: the model
  decides, PL/SQL executes.
- **Tool belts and tables.** Each agent lists two or three tools. Only one
  lights up per scene; the others stay visible but dim. Each tool has a wire
  to a table node that shows real-looking rows. Table names are Oracle-style
  (`PAYMENTS`, `INVOICES`, `REFUND_POLICIES`).

### 2.2 The storyboard

Ten scenes. Each has a camera target, a caption, the transfers that animate,
and the state changes that stay. Timings are a starting point; tune in the
browser.

| # | Title | Camera | What moves | What changes and stays |
|---|-------|--------|------------|------------------------|
| 0 | The system | Whole canvas | Nodes fade in in reading order, wires draw | Everything dim except You |
| 1 | The request | You + Orchestrator | Request chip travels You → Orchestrator | Chat bubble shown |
| 2 | The plan | Orchestrator + model box | Chip goes to the model, "thinking" dots, chip returns | Plan card appears: ☐ Check payments ☐ Check refund rule |
| 3 | Delegate | Orchestrator + Billing agent | Task chip travels Orchestrator → Billing | Billing agent lit |
| 4 | Choose a tool | Billing agent + model box | Chip to model and back; `get_payments` glows, the other two dim | Tool call shown as `get_payments('INV-1003')` |
| 5 | Read your data | `get_payments` + PAYMENTS table | Wire pulses, rows stagger in, two rows highlight | Result chip "2 payments · €49 each" |
| 6 | Report back | Billing → Orchestrator | Result chip travels back | Plan: ☑ Check payments. Chip to model, back with "Ask Policy" |
| 7 | Second specialist | Policy agent + REFUND_POLICIES | Task chip in, `find_policy` glows, rule text appears | `get_customer_tier` stays dim |
| 8 | Combine | Orchestrator + model box | Result chip back, chip to model, "answer" chip returns | Plan: ☑ ☑ |
| 9 | Answer, and the run | Zoom to You, then pull out to whole canvas | Answer chip You; answer bubble appears; camera zooms out | Session summary strip: 3 agents · 2 tool calls · 4 model calls · 1 session |

Scene 9 pulling back out to the whole system is important. It repeats the
shape of the thing the visitor just learned, now fully lit, and the session
summary connects to the code sample right below the animation, which starts
with `generate_session_id`.

Keep the fictional data as it is (`INV-1003`, two payments of €49, the
duplicate-payment refund rule). Add fictional rows for the unused tools only if
they are ever shown; they are not in this storyboard.

---

## 3. Architecture

### 3.1 The camera

Do this with CSS transforms, no library.

- `.af-viewport` is the frame. It has `overflow: hidden`, `position: relative`
  and a fixed aspect ratio (`aspect-ratio: 16 / 9`). Its width is 100 % of the
  content column. Because the aspect ratio is fixed, the frame never changes
  height while playing. No layout shift, no reserved empty areas.
- `.af-canvas` is a child of the viewport with `position: absolute`,
  `width: 1600px`, `height: 900px`, `transform-origin: 0 0`.
- Each scene has a camera rectangle `{ x, y, w, h }` in canvas units. The
  component computes:

  ```ts
  const scale = viewportWidth / camera.w;          // viewport measured with ResizeObserver
  const tx = -camera.x * scale;
  const ty = -camera.y * scale;
  canvas.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
  ```

  Keep the camera rectangle in the viewport's aspect ratio. Write a helper
  `cameraFor(nodeIds, padding)` that takes the bounding box of the named nodes,
  pads it, and expands the shorter side to match 16:9. Scenes then name nodes,
  not coordinates, and the layout can move without retuning every scene.
- `transition: transform 800ms cubic-bezier(0.65, 0, 0.35, 1)` on the canvas.
  Set `will-change: transform` on the canvas only; nothing else.
- Text stays HTML. Scaling with `transform` keeps it vector-sharp at rest and
  selectable. Chrome can blur text for the duration of the transition; that is
  acceptable. Do not try to fix it with `backface-visibility` hacks.
- Order inside a scene: the camera moves first (800 ms), then the scene's
  motion starts. Trigger scene motion with a `setTimeout` equal to the camera
  duration, or from `transitionend` on the canvas with a timeout fallback.
  Then hold. Scene duration = camera + motion + hold.

### 3.2 Data model for `story.ts`

Keep the principle that already holds: every frame is derived from a scene
index, so Previous, Next and Replay can jump anywhere. Extend the types:

```ts
type NodeKind = "user" | "orchestrator" | "agent" | "tool" | "table" | "model";

interface Node {
  id: string;
  kind: NodeKind;
  x: number; y: number; w: number; h: number;   // canvas units
  title: string;
  subtitle?: string;
  /** Color role. Carries through the agent, its tools, its chips and its plan item. */
  tone?: "accent" | "billing" | "policy";
  /** For tools: the agent that owns them. For tables: the tool that reads them. */
  parent?: string;
}

interface Wire { from: string; to: string; }

interface Transfer {
  from: string; to: string;
  kind: "task" | "result" | "model";  // model = the small "thinking" round trip
  label: string;
  /** Milliseconds after the camera arrives. */
  at: number;
}

interface Scene {
  id: string;
  title: string;
  caption: string;
  quote?: boolean;
  /** Node ids to frame. `cameraFor` turns them into a rectangle. */
  frame: string[];
  framePadding?: number;
  /** Nodes drawn at full strength. Everything else is dimmed. */
  active: string[];
  transfers: Transfer[];
  /** Milliseconds to hold after the last transfer ends. */
  hold: number;
}
```

Persistent state (plan items ticked, tool chosen, rows visible, answer shown)
should stay as `...At` indices on the node or in small lookup functions like
today's `toolStateAt`. Do not accumulate state across scenes in React; derive
it from the index.

### 3.3 Component structure

Split `AgentFlow.tsx`, it is at 536 lines and will grow:

```
AgentFlow.tsx              orchestration: clock, controls, camera, a11y
AgentFlow/story.ts         content and timing only (as today)
AgentFlow/camera.ts        cameraFor(), transform math, pure functions
AgentFlow/nodes/*.tsx      one small component per node kind
AgentFlow/Wires.tsx        one SVG overlay in canvas coordinates
AgentFlow/Transfers.tsx    travelling chips
AgentFlow.css
```

Wires and chips become much simpler than today because they live in canvas
coordinates, which are static. There is no more `getBoundingClientRect`
measuring of slots; positions come from `story.ts`. Only the viewport width is
measured, for the scale.

### 3.4 Do not add a dependency by default

CSS transitions and `@keyframes` cover the camera, the chips and the row
stagger. If you find yourself wanting spring physics, `motion` (framer-motion)
is the only library worth considering, and it costs about 30 kB gzip on a page
that is otherwise static. Decide that late, not first.

---

## 4. Visual design

The current version is gray on gray with one indigo accent. Give it hierarchy.

- **Size is hierarchy.** The camera does most of this. In addition, the
  orchestrator is the largest card on the canvas, agents are medium, tools are
  small rows inside their agent, tables are wide and short.
- **Dim, do not tint.** Inactive nodes get `opacity: 0.35` and lose their
  tone color (fall back to gray). Active nodes are at full opacity with their
  tone border and a subtle glow (`box-shadow: 0 0 0 3px color-mix(... 25%)`).
  Do not use `filter: blur()` on many nodes; it is expensive under a transform.
- **Two tones plus the accent.** Orchestrator and its chips use the Starlight
  accent. Billing and everything Billing produces (its tools, its result chip,
  its plan item, its table highlight) use one hue, Policy uses another. The
  visitor can follow a color through the run. Define them once in `.af` with
  `color-mix()` on top of Starlight variables so light and dark mode both work:

  ```css
  .af {
    --af-billing: oklch(72% 0.13 200);   /* teal-ish; check contrast in light mode */
    --af-policy:  oklch(78% 0.14 75);    /* amber-ish */
  }
  :root[data-theme="light"] .af {
    --af-billing: oklch(48% 0.12 200);
    --af-policy:  oklch(52% 0.13 75);
  }
  ```

  Check text on these colors against WCAG AA in both themes.
- **Icons.** One small inline SVG per node kind: person, compass or
  branching-arrows for the orchestrator, robot-ish square for agents, wrench
  for tools, table grid for tables, cloud for the model. Six paths, hand
  inlined in a `Icon.tsx`, 16 to 20 px, `stroke: currentColor`. Do not add an
  icon library. Starlight's `Icon` component is Astro-only and not available
  inside the React island.
- **Model box.** Show generic labels, not vendor logos: "AI model · Claude,
  GPT, Gemini, or a local Ollama model". Logos need brand-guideline review and
  date quickly.
- **The database boundary.** A large rounded rectangle with a dashed or
  low-contrast solid border, a label "Oracle Database" top-left and "UC AI"
  next to it. Faint grid or nothing inside. Do not draw a cylinder icon; the
  label is enough.
- **Caption inside the frame.** Render the caption as an overlay strip at the
  bottom of the viewport, subtitle style, with a translucent background. The
  eye stays in the picture. Keep the same text in the transcript for screen
  readers.
- **Progress rail.** Replace "3 of 8 · Use a tool" with a row of ten small
  labelled dots under the viewport. Each is a button that calls `goTo(i)`.
  Keep Previous, Next and Play/Pause as buttons for keyboard users.
- **One Replay.** The primary button is Play, Pause or Replay. Remove the
  secondary Replay.

---

## 5. Motion spec

Fill the hold time with small, meaningful motion. Every effect should show a
fact about how the system works, not decorate.

| Effect | How | Duration |
|--------|-----|----------|
| Camera move | `transform` transition on the canvas | 800 ms |
| Node reveal (scene 0) | opacity + `translateY(8px)` to 0, staggered 60 ms | 60 ms x nodes |
| Wire draw | SVG `stroke-dasharray` / `stroke-dashoffset` from full length to 0 | 500 ms |
| Task or result chip | travels along the wire. Use `offset-path: path("...")` with the wire's path and animate `offset-distance` 0 % to 100 %. Falls back to a straight `translate` if `offset-path` is unsupported | 700 ms |
| Model round trip | small chip to the model box, three pulsing dots on the model for 600 ms, chip back with the decision text | 1.6 s total |
| Tool choice | chosen tool row scales to 1.04 and gets its tone border; the other rows drop to 0.35 opacity | 300 ms |
| Table rows | rows fade in one by one, 80 ms apart; the matching rows then get a tone background | 80 ms x rows + 300 ms |
| Plan tick | checkbox glyph swaps ☐ → ☑ with a 200 ms scale pop | 200 ms |
| Session summary (scene 9) | counters count up from 0 | 600 ms |

Rules:

- Wires are curved (`C` cubic bezier between node edges, control points offset
  horizontally). Straight dashed lines look like a diagram tool export.
- Chips have a short shadow and a 1 px border in their tone. A task chip is
  filled, a result chip is outlined with a check mark, a model chip is small
  and round.
- Never run two chips at the same time in one scene. One thing moves; the
  visitor follows it.
- Pause freezes everything: camera (`transition: none` snapshot is not
  possible, so apply `animation-play-state: paused` to chips and simply let a
  camera move finish), timers and row staggers. The current `remaining.current`
  clock approach is right; keep it.

---

## 6. Layout and responsiveness

- **Width.** Use the full content column, 100 % of `--sl-content-width`.
  Do not break out of the column with negative margins; on wide screens the
  right-hand "On this page" list is there and the figure would collide with
  it.
- **Expand button.** Reuse the pattern of `FullscreenTable.astro`: a small
  "Expand" button top-right of the viewport that opens the same component in a
  `<dialog>` at up to 1400 px wide. The camera math is width-independent, so
  the dialog needs no extra work. Do it in React inside `AgentFlow.tsx`, since
  the island already owns the state.
- **Aspect ratio.** 16:9 above 55 rem. Below 55 rem switch the viewport to
  4:3 and pass a `viewportAspect` into `cameraFor` so frames stay tight.
  Because the camera zooms in, a phone shows one agent at a legible size,
  which is a big improvement over the current stacked mobile layout. Test at
  390 px wide.
- **Idle state.** Before Play, show scene 0's end state (whole system, dim,
  with You lit) and the caption "A customer asks one question. Follow it
  through the agents that answer it." No reserved empty areas exist anymore.
- **Autoplay.** Start playing when the viewport is at least 50 % in view
  (the `IntersectionObserver` is already there), unless
  `prefers-reduced-motion` is set. Pause when it leaves the view or the tab
  hides. Stop at the end; do not loop. The visitor can press Replay. The
  animation runs longer than five seconds, so Pause must always be one click
  away (WCAG 2.2.2).

---

## 7. Accessibility

Keep everything the current version does right, and adapt it to the camera:

- `prefers-reduced-motion`: camera jumps without a transition, chips render
  at their destination, rows appear at once. Scenes still advance with Next.
  Do not autoplay.
- The `role="status"` live region announces "n of 10 · title" only on manual
  steps, never during autoplay. Keep this.
- The "Read the story" `<details>` transcript stays and gains the new content:
  the plan, the tool chosen and the tools not chosen, the rows, the rule, the
  session summary.
- All nodes inside the canvas are `aria-hidden="true"`. The canvas is a
  picture; the transcript and the caption are the accessible content. Mark
  the caption with `aria-live="off"` so it does not double-announce.
- Progress rail dots are `<button aria-label="Scene 4 of 10: Choose a tool"
  aria-current="step">`.
- Focus rings on every control, 2 px in the accent, as today.
- Contrast: check every text on a tone color in both themes. `oklch` values in
  section 4 are starting points, not tested.

---

## 8. Implementation order

Do it in this order so the page works at every commit.

1. **Bugs first, on the current version.** Remove the duplicate Replay
   button, the duplicate light-theme CSS block, and the unused `ANSWER_SCENE`
   export. Commit.
2. **Camera and canvas without content changes.** Add `camera.ts`,
   `.af-viewport`, `.af-canvas`, fixed aspect ratio, `cameraFor`. Give the
   existing four nodes canvas coordinates. Replace slot measuring with canvas
   coordinates. Chips and wires now use static positions. Visually the result
   should look like today, just inside a zoomable frame. Commit.
3. **New nodes and story.** Add the database boundary, the model box, the tool
   belts, the two tables, the plan card. Rewrite `SCENES` to the ten-scene
   storyboard. Wire up camera frames. Commit.
4. **Visual design.** Tones, dimming, icons, curved wires, in-frame caption,
   progress rail. Commit.
5. **Motion.** Per the table in section 5, one effect at a time. Check the
   pause path after each. Commit.
6. **Responsive and expand.** 4:3 below 55 rem, the `<dialog>` expand.
   Commit.
7. **Autoplay and a11y pass.** Section 6 and 7 checklists. Commit.

Update the "How UC AI runs this" `<details>` in `index.mdx` after step 3 so it
matches what the picture shows (model box, tools chosen and not chosen,
session). `index.mdx` keeps its persuasive voice; only mechanics follow the
docs style rules.

---

## 9. Definition of done

- `bun run build` in `docs/` passes.
- At 1440, 1024 and 390 px wide, in light and dark mode: no layout shift while
  playing, every caption readable, every zoomed-in scene has no clipped node.
- With `prefers-reduced-motion: reduce` emulated in DevTools: no transitions,
  no autoplay, Next and Previous work, transcript complete.
- Pause during a camera move, during a chip travel and during a row stagger.
  Resume continues from where it stopped, does not restart the scene.
- Tab from the page heading through every control and the transcript.
- The last scene shows the session summary and one Replay button.
- A visitor who has never seen the site can say, after one autoplay: "the
  orchestrator asks the model what to do, the specialists call PL/SQL
  functions on the database's own tables, and the whole thing runs in Oracle".
  Test this on one colleague who did not build it.
