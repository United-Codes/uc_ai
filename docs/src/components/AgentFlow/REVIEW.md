# AgentFlow review, second iteration

Reviewed: commits `3c9fb38` and `2bfa5b1` plus the unstaged changes in
`AgentFlow.tsx`, `AgentFlow.css`, `AgentFlow/story.ts` and `index.mdx`, as of
2026-09-10. Checked in the browser at 1440 px in dark and light mode, at 390 px
with phone emulation, and with the Expand overlay open.

Short version: the architecture is right and should stay. The camera over one
canvas, the story as data, one clock that drives every effect, chips that ride
the wire through `offset-path`, exact pause, reduced motion, the transcript.
All of that is clean and I would not touch it. What is not finished is the
picture itself: text is too small in half the scenes, chips land on top of the
thing they are about, the tool never looks like a database function, the
controls are misaligned and wrap, and the Expand overlay renders behind the
site header and the sidebars. Every one of these has a concrete cause and a
concrete fix. They are listed below in the order I would do them.

---

## 1. Controls are misaligned and wrap

**What you see.** Play sits 8 px higher than Previous and Next. The scene
rail wraps to a second row with two orphan pills ("Combine", "The answer") at
777 px, and to three rows on a phone. The Expand button covers canvas content
in the top right corner, on the phone it covers the PAYMENTS table.

**Cause.** Starlight's markdown stylesheet adds `margin-top: var(--sl-content-gap-y)`
to every element that follows a sibling inside `.sl-markdown-content`
(`node_modules/@astrojs/starlight/style/markdown.css`, first rule). Inside
`.af-controls` the first child (Play) gets no margin and every later child
gets 16 px. The `.af :where(div, p, ol, …)` reset in `AgentFlow.css` does not
list `button`, so it does not catch this. Measured: Play `margin-top: 0`,
Previous `margin-top: 16px`.

The rail wraps because ten labelled pills are about 900 px wide and the
column is 777 px.

**Fix.**

1. Put Starlight's own opt-out class on the figure: `<figure className="af not-content">`.
   The sibling rule excludes `:where(.not-content *)`. Then delete the
   `:where(...)` margin reset; it is no longer needed.
2. Redesign the control row so it fits in one line at 358 px and up:

   ```
   [ ▶ Play ]  [ ‹ ]  [ › ]   ● ● ● ● ● ○ ○ ○ ○ ○   6 / 10 · Read your data
   ```

   Ten small dots (buttons, 12 px, `aria-label="Scene 6 of 10: Read your
   data"`, `aria-current="step"` on the current one), then the current
   position and title as text. Previous and Next become icon buttons with
   `aria-label`. Drop the labelled pills. The titles stay reachable through
   the dots' `title` attribute and the transcript.
3. Move Expand out of the viewport into the right end of the control row.
   Nothing then sits on top of the picture.

---

## 2. The Expand overlay renders behind the page chrome

**What you see.** With Expand open at 1440 px, the site header, the left
sidebar and the "On this page" list all paint above the overlay. The left
third of the canvas is hidden behind the sidebar. The page behind still
scrolls.

**Cause.** Starlight's `TwoColumnContent.astro` sets `isolation: isolate` on
`.main-pane`. That creates a stacking context, so the `z-index: 90` of
`.af-scrim` and `91` of `.af-shell` only count inside the main pane. The
header (`--sl-z-index-navbar: 10`), the sidebar (`--sl-z-index-menu: 5`) and
the workshop banner (`z-index: 10`) live in the root stacking context and win
regardless of how large our number is.

**Fix.** Use the browser's top layer. It beats every stacking context.

Wrap `.af-shell` in a real `<dialog>` that is always in the DOM, so the
viewport element and its refs never remount:

```tsx
<dialog ref={dialogRef} className="af-dialog" onClose={() => setExpanded(false)}>
  <div className="af-shell">…</div>
</dialog>
```

```ts
// expand
dialog.close();          // showModal() throws if `open` is already set
dialog.showModal();
// collapse
dialog.close();
dialog.show();           // back into normal flow
```

- Call `dialog.show()` once on mount, so the collapsed state is an open,
  non-modal dialog in normal flow. Override the UA styles for that state:
  `position: static; inset: auto; margin: 0; padding: 0; border: 0;
  background: transparent; width: auto; max-width: none;`.
- Style the modal state with `.af-dialog:modal { width: min(1400px, 100vw - 2rem); … }`
  and the scrim with `.af-dialog::backdrop`. Delete `.af-scrim` and the
  `role="dialog"` / `aria-modal` attributes; the element provides them.
- The Escape key fires `cancel` then `close`, so the `onClose` handler keeps
  React state in sync. Focus is trapped by the browser. Return focus by hand
  as today.
- Set `document.documentElement.style.overflow = "hidden"` while modal and
  clear it on close, so the page does not scroll behind the overlay.
- The `ResizeObserver` on the viewport already fires when the width jumps to
  1400 px, so the camera recomputes. Cap the zoom (section 4.6), otherwise a
  two-node scene at 1400 px gives 33 px chip text.

---

## 3. Chips land on top of the text they explain

**What you see.**

- Scene 3: the decision chip "Payments first, then the refund rule" settles
  over the word "Orchestrator" and the UC AI badge.
- Scene 5: the decision chip covers the "Billing agent" title.
- Scene 6: `get_payments('INV-1003')` covers the first PAYMENTS row.
- Scene 8: `find_policy(...)` covers the "Duplicate payment" row.
- Scene 7 stepped to by hand: all three of the scene's chips sit on their
  destinations at once, two of them stacked on the orchestrator.
- Phone, scene 6: the chip arrives from off frame and stays clipped at the
  left edge, half a word visible.

**Cause.** `Transfers.tsx` moves a chip along `wirePath(from, to)`, whose
end point is the destination's edge, but at `progress = 1` the `offset-path`
places the chip's anchor at that end point and the chip box extends inward
over the card. The chip then stays for the rest of the scene, because nothing
sets it to fade. With `settled` true, every transfer of the scene renders at
100 %.

**Fix.** Two rules.

1. **A chip is a messenger, not a label.** It fades out 400 ms after it
   lands, and the destination's persistent state carries the information
   (the tool row lights, the rows appear, the plan ticks, the answer bubble
   pops). Drive the fade from the same clock:

   ```ts
   const after = raw - 1;                       // seconds past landing, in TRAVEL_MS units
   const opacity = raw < 1 ? 1 : Math.max(0, 1 - (motion - transfer.at - TRAVEL_MS) / 400);
   ```

   When `settled` (manual step, reduced motion), render no chips at all.
   Every fact a chip carried is already visible in the node state at the end
   of the scene. Check this scene by scene; if one is not (for example the
   "What should we check?" question), the node state is missing something,
   not the chip.

2. **Land at the wire, not on the card.** Move the chip's anchor so its box
   ends where the wire ends: `offset-anchor` is not supported everywhere, so
   set `--af-anchor-x/-y` from the wire's direction and translate the inner
   span by `-100%` or `0` on the axis of travel. Or simpler: end the path
   20 canvas units short of the card edge (`wirePath(from, to, { shorten: 20 })`).
   Combined with the fade, no chip ever obscures text for more than a
   moment.

Also make sure the decision chips that come back from the model carry text
that ends up somewhere. "Payments first, then the refund rule" is the plan
card, good. "A duplicate. Ask Policy about refunds" is nowhere after the chip
fades; give the plan card a one-line "note" slot under the items, or drop the
sentence to "Ask Policy".

---

## 4. Text is hard to read

There is no single cause. Six things add up.

### 4.1 The far scenes shrink everything to 11 px

Scene 1 and the pull-out in scene 10 frame the whole canvas. At 777 px that
is scale 0.43: titles render at 11 px, tool names at 8 px, the boundary label
at 14 px. On a phone it is scale 0.2. `is-far` hides the subtitles, but the
tool rows and the table headers stay and turn into grey noise.

Fix: give the far mode its own typography instead of hiding things. When
`is-far`, hide tool rows and tables' bodies too, and grow the titles:

```css
.af-canvas.is-far .af-node-title { font-size: 44px; }
.af-canvas.is-far .af-table-name { font-size: 40px; }
.af-canvas.is-far .af-node--tool { display: none; }
```

The cards have the room; they are mostly empty at that scale anyway. The
far view should read as a block diagram with eight big words, not as a
shrunken copy of the near view. Change `far` to a class on the canvas only
(it is) and keep the threshold at 0.56.

### 4.2 The overview letterboxes

The camera aspect is `viewport.w / (viewport.h - caption)`, about 2:1, but the
canvas is 16:9. `cameraFor([])` fits the whole canvas into a 2:1 rectangle,
so the establishing shot has empty panel on both sides (visible in the
scene 1 screenshot, 40 px each side). Meanwhile the caption height changes
with the text (46 px for one line, 70 px for two), so the aspect changes
between scenes and the camera nudges by a few pixels when the caption wraps.

Fix: take the caption out of the measured area. Put it *below* the viewport
as a two-line, fixed-height strip inside the frame, and set the viewport's
aspect ratio in CSS only (16:9 desktop, 4:3 phone). Then delete `captionRef`,
`viewport.caption` and `stageHeight`; `aspect` becomes the CSS ratio. The
session strip no longer needs protecting from the caption either.

If you want the caption to stay inside the picture, keep it as an overlay but
give it `min-height: 2 lines` and reserve that height as a fixed 60 canvas
units at the bottom of every camera rectangle. Fixed is the point; measured
is the bug.

### 4.3 The boundary label is huge and always cropped

`ORACLE DATABASE` is 32 px uppercase with letter spacing. In every zoomed
scene it is cut off at the left edge ("ACLE DATABASE", "CLE DATABASE",
"BASE"), because the camera frames nodes and the label sits at the boundary's
top-left corner. Its size also makes it the loudest element on the canvas.

Fix: take it off the canvas. Render a small badge in the viewport corner as
normal HTML, "Inside your Oracle Database", shown whenever the camera
rectangle is inside the boundary and swapped to "Outside: the AI model" when
the model box is in frame. The boundary itself stays as the dashed rectangle,
and a 22 px label can stay at the top-left for the far view only
(`.af-canvas:not(.is-far) .af-boundary-label { display: none }`).

### 4.4 Dimmed nodes are grey smear

`opacity: 0.32` on a card full of text leaves ghost paragraphs the eye still
tries to read (the "You" bubble in scenes 3 and 5). Fix: dim the card to 0.5
and hide its body: `.af-node.is-dim > :not(.af-node-head) { visibility: hidden }`.
The title stays as a landmark; nothing half-legible competes with the lit
node.

### 4.5 The small tags never reach a readable size

`your PL/SQL` is 14 px canvas units; at the usual 0.75 to 0.85 scale that is
10 to 12 px, and on the phone 10.7 px. Either raise it to 17 px or replace it
with the code card from section 5, which makes the tag redundant.

### 4.6 Expanded, the text is too big

At 1400 px a two-node frame gives scale 1.7. Cap it in `cameraFor` by
enforcing a minimum camera width:

```ts
const minW = viewportWidth / MAX_SCALE;   // MAX_SCALE = 1.15
if (rect.w < minW) rect = fitAspect(grow(rect, minW), aspect);
```

Then Expand shows more context, not bigger letters.

---

## 5. The tool must look like a database function

Today a tool is a monospace name, a tiny "your PL/SQL" tag, and a chip that
reads `get_payments('INV-1003')`. A visitor who does not know UC AI cannot
tell whether that name is an API call, a Python function, or a SQL statement.
The caption says it, the picture does not.

**Proposal.** When a tool is chosen, its row expands into a code card:

```
ƒ get_payments                      PL/SQL function
  select payment_id, amount, status
  from   payments
  where  invoice_id = :p_invoice     -- 'INV-1003'
```

- Give the tool node a `chosenH` (about 130 canvas units) and let `Tool`
  render the SQL body when `toolChosenAt`. The Billing agent card grows from
  250 to about 330; move the Policy agent and its table down by 80. The
  canvas has the room (nothing sits between 760 and 900 except the session
  strip).
- Store the SQL in `story.ts` as `tool.sql: string[]`. Keep it to three
  lines and real Oracle syntax with a bind variable. A reader who knows
  PL/SQL should nod, not wince.
- Rename the tag to `PL/SQL function` and drop it from tools that are not
  chosen (they show only the name).
- Give the tables a header row (`INVOICE_ID · AMOUNT · STATUS`) and add the
  `invoice_id` column with `INV-1003` on the two matching rows and `INV-0977`
  on the first, so the `where` clause visibly selects them. Title the node
  `table PAYMENTS` with the table icon.
- Add a short return chip from the table back to the agent, "3 rows → JSON",
  so the loop closes: model chose, PL/SQL ran, result went back. Without it
  the data flow ends at the table.
- Captions:
  - Scene 5: "The model does not run code. It picks one of your functions
    and its arguments."
  - Scene 6: "UC AI calls get_payments. Your PL/SQL runs SQL on your table.
    Nothing leaves the database."
  - Scene 8: same shape for find_policy.

This is also where the value of UC AI is stated, so give the model box a
second line in scenes 5 and 6: "receives: function name + arguments, returns:
the rows as JSON". One line under the title. The visitor then sees what
crosses the boundary and what does not.

---

## 6. Smaller findings

1. **Empty session strip.** `Summary` renders a dashed, empty rectangle
   from scene 1 through 9 (visible at the bottom of the scene 1 screenshot).
   Return `null` until `summaryVisibleAt`, and take it out of the scene 0
   reveal.
2. **The answer disappears in the pull-out.** In scene 10, once the camera
   pulls out, `is-far` hides the answer bubble, so the picture never shows the
   answer at the end. Keep the answer visible in far mode (it is one short
   paragraph), and switch the caption to `CLOSING` at `frameThenAt`.
   `CLOSING` is currently only in the transcript.
3. **`--sl-content-width: 60rem` does little.** At 1440 px the column is
   still 777 px, because the sidebars are fixed and the grid gives the rest.
   It only widens the page above about 1700 px, and it widens every block on
   the page. Keep it knowingly or remove it; the camera makes the animation
   legible at any width.
4. **Every frame re-renders the tree.** The clock sets `elapsed` state on
   each animation frame, so `AgentFlow` and its children reconcile at 60 fps
   even during the hold. `NodeView` is memoised, but `Transfers` and the
   camera memo run every frame. Not visible yet; if the code card adds
   weight, gate `setElapsed` to frames where something clocked is active
   (`motion < lastMovement + 600` or a table is filling).
5. **`durationOf` duplicates constants.** It uses `NODES.length * 60` while
   `AgentFlow.tsx` has `REVEAL_STAGGER_MS = 60`. Move the constant to
   `story.ts` and import it.
6. **No focus trap on the current overlay.** Tab leaves the fake dialog and
   lands in the page behind. The `<dialog>` fix in section 2 solves it.
7. **Thumbnail scene 7 by hand shows three chips.** Covered by section 3;
   listed here so it is not forgotten when checking the manual stepping path.
8. **Light mode** is fine. Tone contrast on `--af-on-tone: #fff` over the
   47 % and 46 % oklch tones is above 4.5:1. Dim cards at 0.32 on white are
   very faint but that is the intent.
9. **Docs sentence.** The `<details>` text in `index.mdx` says "UC AI runs
   that tool as your PL/SQL function". After section 5, add one sentence:
   "The function runs SQL against your tables, so the data never leaves the
   database." Keep the persuasive voice; `index.mdx` is exempt from the docs
   register rules.

---

## 7. Suggested order

| # | Work | Section | Size |
|---|------|---------|------|
| 1 | `not-content` on the figure, one-row controls, Expand into the row | 1 | small |
| 2 | Real `<dialog>` with `showModal()`, scale cap | 2, 4.6 | medium |
| 3 | Chips fade after landing, none when settled, land short of the card | 3 | medium |
| 4 | Code card, table header, return chip, new captions | 5 | large |
| 5 | Caption out of the measured area, far typography, boundary badge, dim body, tag size, empty strip | 4, 6.1 | medium |
| 6 | Closing caption, content width decision, constants, rAF gating | 6 | small |

Check after each step at 1440 px dark and light, at 390 px with the phone
emulation, with Expand open, and with `prefers-reduced-motion: reduce`. Step
through all ten scenes by hand once; that path renders every settled state
and is where stacked chips and empty shells show up.

---

## 8. What is good and should stay

- `camera.ts` and `geometry.ts` are pure and small. `cameraFor(rects,
  aspect, pad)` is exactly the API the first guide asked for.
- Story as data with `...At` predicates. Any scene reachable from an index.
- One clock in `elapsed`, and every effect reading it. Pause is exact, and
  the rows, the counters and the chips all stop together.
- Chips on `offset-path` with a `@supports` fallback.
- Reduced motion handled at the root (`af-static`, `settled`), not per
  effect.
- The transcript is complete and reads well on its own.
- Node components never measure anything.

Keep those. Fix the picture.
