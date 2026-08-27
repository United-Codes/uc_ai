# Docs Voice: unexcited, frictionless, no narrator

The register every page in `docs/src/content/docs/` is written in. Names the
sentence shapes that mean a draft has slipped into essay voice, and gives a grep
for each one.

This is the **register** rule. It sits on top of the `simple-english` skill,
which governs sentence mechanics (ASD-STE100: sentence length, one word one
meaning, active voice, simple tenses). Both apply to the same page. STE tells
you how to build a sentence; this tells you which sentences should not exist.

## Trigger

Before you write or edit any page under `docs/src/content/docs/` — guides,
reference pages, provider setup pages, tutorial lessons, release notes. Also
when asked to fix the tone, voice, or register of docs, to remove narrator or
essay voice, or to review a docs page for how it reads rather than what it says.

For a full tutorial course, read `write-tutorial-guide.md` as well. That skill
owns structure — the thread, the lesson skeleton, redundancy against the
reference guides. This skill owns voice, on every page.

## The two exceptions

The landing page (`docs/src/content/docs/index.mdx`) and
`docs/src/content/docs/guides/use-cases.mdx` keep their persuasive voice. Fix
only mechanics there. Everywhere else, this skill applies in full.

## The rule

The reader wants a **neutral, unexcited page they can scan**. They do not want a
documentary.

**Write like a well-edited Oracle manual.** Not like Anthropic Academy, not like
a launch post, not like a teacher performing enthusiasm. STE already bans most
of this register. Do not override it with "framing that wins attention".

Motivation is a **recorded failure**, not a paragraph that tells the reader to
feel the pain. Keep "Without X ... With X" as a two-line contrast. Do not wrap it
in an essay about why it matters.

The origin of this rule, kept because it is the clearest statement of it: the
owner's review of Claude-written lessons, condensed — *the prose is fancy, not to
the point.*

### Headings structure the page

Headings become the right-hand **On this page** list. That list is navigation. A
heading that comments, teases, or only makes sense after you have read the
section fails at its one job: helping the reader jump.

The test is not "is this heading true?" It is: **cover the body. From the heading
list alone, can you find the block you need?**

Real headings that failed this test:

| Rejected | Why it fails as structure | Write instead |
| --- | --- | --- |
| `Where this approach stops` | a verdict; the TOC cannot tell you this is "ask about remaining credit" | `A question the pasted rows cannot answer` |
| `Two things that will surprise you` | tease; "surprise" is the writer's feeling | `Memory tags stay on the old profile version` |
| `Why your code cannot use this answer` | essay title | `The same PDF returns different wording` |
| `The next shift starts from nothing` | literary | `Two conversations, a week apart` |
| `An agent that reads its attacker's mail` | a headline | `A supplier email changes a bank account` |
| `The question that needs twenty-six tool calls` | punchy, not a topic | `One question, twenty-six tool calls` |
| `Where the cheap model reliably breaks` | verdict; `reliably breaks` is your conclusion, not the topic | `The cheap model on a scanned invoice` |
| `What reasoning did, and did not do` | verdict shape; the TOC cannot tell you this is the cheapest model | `Reasoning on the cheapest model` |
| `What the model can and cannot talk its way past` | tease; needs the body to be understood | `An "ignore your instructions" prompt` |

Do **not** write headings that:

- judge (`stops`, `fails`, `matters`, `the honest...`)
- tease (`will surprise you`, `the one that...`, `nothing strange`)
- need the next sentence to be understood

Do write headings that name the **object or the action**: `Set up the demo
schema`, `Create the prompt profile`, `Ask about remaining credit`,
`Verification`. Page titles, lesson titles and `Aside` titles follow the same
rule. Vivid is not a goal. Neutral is.

### Body: state the fact, then the next step

Do not comment on the fact. Do not defend the model. Do not tell the reader how
to feel. Do not recap what the section was "really about".

From lesson 1 of Build an Agent, the paragraph the owner pointed at:

**Rejected:**

> The model did nothing strange. It saw a total of 200, it saw no credit
> information, and it assumed the total was available. The reasoning is good.
> The data was incomplete, and nothing in the prompt said so.
>
> This is the failure that matters, because it is quiet:

**Write instead:**

> The prompt sent a total of 200 and no credit data. The model answered 200. The
> remaining credit on INV-1003 is 0.
>
> This approach has three limits:

Same facts. No narrator. The heading above that block names the question, not
the writer's verdict on the approach.

### Sentence shapes that mean you have slipped into essay voice

A list of banned phrases only catches the phrases somebody already caught. These
are the **shapes**, each with the grep that finds it. Every example below is a
real sentence that shipped in the UC AI docs and was later cut.

**Read the greps as a starting point, not as the job.** See [what the greps are
worth](#what-the-greps-are-worth) before you trust a quiet result.

**1. The demonstrative recap.** Points back at the block you just read, and names
no new thing.

> ~~That is the control.~~ ~~That is the whole course in four rows.~~ ~~This is
> the whole idea of code mode.~~ ~~**Keep everything, hide the agent.** This is
> the usual one.~~

Test: delete it. If no fact is lost, it was narrator. Often the fix is to fold
the noun into the next sentence: `That is the control. It holds whatever the user
types` becomes `The control holds whatever the user types`.

```bash
grep -nE '(That|This|These|Those) (is|are|was|were) ' <file>
```

**Do not anchor this one to `^`.** An earlier version of this skill used
`^(That|This) (is|was) ` and it saw 26% of the candidates: in a file wrapped at
80 columns a recap almost never starts a line, and in a file with one paragraph
per line it never does. Four independent reviewers hit this. The unanchored form
returns roughly 1 real defect in 6; the noise is table cells (`| ... | It is ...
|`), which you can drop with `grep -v '|'`.

**2. The attention imperative.** Tells the reader to look at text they are
already reading.

> ~~Read the fourth line again.~~ ~~Look at what the small model got wrong:~~
> ~~Notice what those branches do not do.~~ ~~Read those two numbers together.~~

Two things this shape does not cover. An imperative that directs **work** is
good: `Run the first block`, `Compare its field names against the JSON your
handler builds`. An imperative that points **forward at a block the reader is
about to read** is also good: `Look at what is missing from these schemas:` above
a code block earns its line. The defect is pointing **back at prose already
read** — there, state the fact instead.

```bash
grep -nE '(^|\. )(Read|Look at|Notice|Watch|See) (that|this|those|these|what|how|it|again)\b' <file>
```

Anchor this one to sentence start, the opposite of shape 1. Unanchored it matches
`you can see how the workflow behaves`, which is a capability statement and not a
defect.

**3. The pre-emptive defence.** A clause that insists your list or your design
choice was considered, without giving the reason.

> ~~Three details are not decoration:~~ ~~Each one earns its place.~~ ~~The
> similarity to CSV is intentional.~~ ~~This is an intentional trade-off:~~
> ~~This escape hatch therefore cannot corrupt the request.~~

If a reason follows, keep the reason and drop the defence. `The commit is inside
the loop on purpose. One document is one unit of work, and a bad PDF at the end
of a run of a hundred must not undo the ninety-nine before it.` earns it — the
second sentence is the reason. `Three details are not decoration:` does not.

The reason can also come **first**, with the defence trailing it. Same defect,
same fix: `UC AI ignores a value for these keys and writes it to the log. ~~This
escape hatch therefore cannot corrupt the request that the framework built.~~`

```bash
grep -nE '\b(not decoration|earns its place|deliberate(ly)?|intentional(ly)?|on purpose|by design|not an accident|not a strawman)\b' <file>
```

False positive to expect on a guide: `deliberate` and `deliberately` also carry a
literal technical meaning (`an action the model must call deliberately`,
`reaches a conclusion by deliberate thought`). Read before you cut.

**4. The superlative closer.** Ends a block by ranking it instead of ending it.

> ~~the only honest way to know~~ ~~the only evidence that counts~~ ~~This is the
> check that matters~~ ~~**Input schemas matter**~~ ~~This helps most when~~
> ~~This is the most flexible pattern~~ ~~A loud error is better than a number
> computed from nothing.~~

```bash
grep -nE '\bthe only\b|\bmatters?\b|\bmatters most\b|\bhelps most\b|\bthe one that\b|\bbetter than\b|\bthe (best|fastest|most) \w+' <file>
```

False positive to expect on a guide: `the only` is usually a factual count, not a
superlative (`the only required parameter`, `the only channel in or out`, `the
only enforcer`). On one review it produced 6 hits and 0 defects.

**5. Reader mind-reading.** Tells the reader what they expect, what they are, or
what everybody else does. Includes the rhetorical question.

> ~~Everybody asks this, so the course measures it.~~ ~~This is the part people
> expect to break, and it does not.~~ ~~That surprises most people.~~ ~~New to AI
> terminology?~~ ~~Prefer code over clicking through an app?~~ ~~First time
> building an agent?~~

```bash
grep -nE '\beverybody\b|\bmost people\b|\bpeople expect\b|\bworth\b|\?$' <file>
```

`?$` on a prose line is near-exact on a reference page, where a genuine question
rarely ends a paragraph. It also catches question-form `Aside` titles and
headings, which are the same defect in a heading slot.

**6. The importance marker.** Says the thing next to it is important. It trails
as often as it leads.

> ~~The consequence is important:~~ ~~and they are the whole point of the
> lesson~~ ~~and the reason is worth copying~~ ~~Two of those deserve
> attention:~~ ~~Most notably, `p_input` receives an array~~ ~~The advantage is
> clear:~~ ~~This log helps most when~~

```bash
grep -nE '^(Most notably|Note that|Importantly|The (advantage|point|consequence|value) is)|\bdeserve attention\b|\bthe whole point\b|\bworth (copying|noting|writing down)\b' <file>
```

**7. The promise-line trailer**, a clause that sells the page instead of naming
its outcome. On a tutorial lesson this lives in the `promise=` prop, and an
em-dash inside that prop is nearly always the trailer:

```bash
grep -n 'promise="[^"]*—' <file>
```

The same defect appears in a reference page as a frontmatter `description:` that
advertises rather than describes (`A comprehensive list of all releases`,
`Interactive tool ... with an easy-to-use interface`). **Do not filter
`description:` out of your self-check** — it is a defect site, not noise.

**8. The unmeasured quality claim.** The dominant defect in reference prose, and
the one the first seven shapes missed entirely. A guide states properties of a
product rather than narrating a run, so the writer reaches for an adjective
instead of a measurement. It has four faces:

- **the self-rating adjective** — ~~a scannable reference~~, ~~This is useful
  when you want to~~, ~~OpenAI provides powerful embedding models~~
- **the capability blurb** — ~~provides integration with X's models, allowing you
  to use state-of-the-art language models~~, ~~Advanced reasoning
  capabilities~~. The `, allowing you to <benefit>` clause almost always deletes
  with no loss.
- **the evaluative predicate** — ~~a page submit that waits five seconds is a bad
  page~~, ~~the conversations that made people unhappy~~, ~~The data quality
  therefore stays high~~. Replace the grade with the mechanism: `blocks the
  user`, `with a negative rating`.
- **the difficulty rating** — ~~This example is more advanced.~~, ~~The clock-in
  tool is more advanced, because it needs parameters.~~ The reader decides what
  is hard.

```bash
grep -nEi '\b(useful|handy|powerful|convenient|scannable|simply|easy|easily|easiest|fastest|seamless|robust|sophisticated|comprehensive|elegant|intuitive|straightforward|state-of-the-art|cutting-edge|frontier|advanced|enhanced|effortless|showcas|unleash|capabilities|more advanced|the hard part|coming soon)\b|, allowing you to |!$' <file>
```

No emoji and no exclamation mark in body prose. A shipped `🎉` on a verification
sentence is the purest violation of "unexcited" in the whole corpus, and no word
grep finds it:

```bash
grep -nP '[\x{1F300}-\x{1FAFF}\x{2700}-\x{27BF}]' <file>
```

**9. The first-person author.** "No narrator" includes the author's own `I`. A
reader cannot act on `I noticed` or `In my experience`.

> ~~In my experience, Anthropic is the best provider for tool calls today.~~ ~~I
> plan to add more providers.~~ ~~I noticed that enabling reasoning can help.~~
> ~~please contact me ... please let me know~~ ~~I recommend that both match.~~

Use institutional `we` for a recommendation or a plan (`We recommend`, `We plan
to add`), or drop the frame and keep the instruction (`We generally recommend
also setting Valid for URLs` becomes `Also set Valid for URLs`). `we` inside a
code comment or a quoted prompt is fine and is not this shape.

```bash
grep -nE '(^|[^A-Za-z`])I( |.(m|ve|ll) )|\bin my experience\b|\bcontact me\b|\blet me know\b|\bwe (generally )?recommend\b' <file>
```

**Do not launder an opinion into a fact.** This is the one way a voice pass can
make a page worse, and it has happened: `In my experience, Anthropic is the best
provider for tool calls today` was rewritten to `Anthropic gives the most
reliable tool calls today`. The narrator went, and a hedged opinion became an
unhedged superlative — shape 8 in place of shape 9. When you remove the author,
keep the hedge or attribute the claim: `We recommend Anthropic for tool calls
today`.

Original instances of these shapes, kept because they are the review that started
this list: "the model did nothing strange / is not wrong / the reasoning is good",
"this is the failure that matters", "that is what the rest of the course builds",
"that is the point of this lesson", "read that carefully", "now the honest part",
"two things that will surprise you", "nothing was invented", "quietly" used for
drama rather than a technical meaning, "now imagine writing the PL/SQL that...".

### Two things the shapes do not catch

**A section whose whole job is commentary.** `## What just happened` followed by
four sentences of recap is not a sentence defect, it is a section defect, and
deleting it is a restructure rather than a voice pass. Report it; do not remove
it inside a voice pass.

**A story told in past tense.** On a reference page current behaviour is present
tense, so a past-tense clause is a signal that the writer started narrating: `Such
a handler changed its meaning when the run context came ... The signature stayed
the same and the code kept compiling, so nothing showed the change.` Rewrite to
the present-tense fact. `grep -nE '\b(stayed|kept|came|used to|once|turned out|back then)\b'` finds some of them.

## What the greps are worth

**The greps are a tutorial tool. On any other page, reading is the job.** This is
the single most repeated finding from the reviews, measured independently eight
times:

| Page type | Grep hits | Real defects found by grep | Found by reading |
| --- | --- | --- | --- |
| Tutorial lesson | 54 lines / 7 files | ~30 | the rest |
| Reference guide | 3 lines / 2688 lines | 0 | 11 of 11 |
| Dense guide (`tools.mdx`) | 0 | 0 | 7 of 7 |
| Setup / ops guide | 5 lines / 11 files | 0 | 8 of 8 |
| Provider page | 2 lines / 8 files | 1 | 45 of 46 |
| `other/` + `help/` | 4 lines / 5 files | 0 | 12 of 12 |

A quiet grep does not mean a clean page. Budget for a full read of every file,
and treat the greps as a way to re-check yourself afterwards.

**How much the round-2 greps bought.** Replayed against the 135 prose lines that
a full eight-reviewer pass actually removed or replaced across 38 docs pages:

| | flags a real defect |
| --- | --- |
| the round-1 composite (phrase-ish, anchored shape 1) | 8 of 135 — **6%** |
| the round-2 composite above (9 shapes, unanchored) | 66 of 135 — **49%** |

Half is the ceiling to plan around. The other half was found by reading, and no
grep in this file will find it.

Which shapes are live depends on the page type. On a **setup or provider page**
expect shapes 2, 4, 5, 6 and 7 to be inert and shapes 8 and 9 to carry almost
everything. On a **tutorial lesson** expect the reverse.

## Self-check before you ship a page

1. Read only the headings, in order, as they appear in **On this page**. Each
   one must name a topic you could jump to. Report any that comment — see the
   heading rule above for why you should usually not rename one.
2. Strip fenced code blocks, then run the union of every shape grep. On a
   code-dense page most raw hits are prompt strings inside `sql` blocks:

   ```bash
   awk '/^```/{f=!f;next} !f' <file> | grep -nEi \
     '(That|This|These|Those) (is|are|was|were) |(^|\. )(Read|Look at|Notice|Watch|See) (that|this|those|these|what|how|it|again)\b|\b(not decoration|earns its place|deliberate(ly)?|intentional(ly)?|on purpose|by design|not an accident|not a strawman)\b|\bthe only\b|\bmatters?\b|\bhelps most\b|\bthe one that\b|\bbetter than\b|\bthe (best|fastest|most) \w+|\beverybody\b|\bmost people\b|\bpeople expect\b|\bworth\b|\?$|^(Most notably|Note that|Importantly|The (advantage|point|consequence|value) is)|\bdeserve attention\b|\bthe whole point\b|\b(useful|handy|powerful|convenient|simply|easy|easily|fastest|seamless|robust|sophisticated|comprehensive|elegant|intuitive|straightforward|state-of-the-art|cutting-edge|advanced|enhanced|effortless|showcas|capabilities|more advanced|coming soon)\b|, allowing you to |!$|(^|[^A-Za-z`])I( |.(m|ve|ll) )|\bin my experience\b|\bcontact me\b'
   ```

   Keep this in sync with the individual shape greps: an earlier version of this
   block silently dropped `better than`, `people expect` and `not a strawman`,
   so the thing people actually run was weaker than the thing they read.

   Filter `title:` frontmatter and `LinkCard` props with `grep -vE ':title:|title="Next lesson'`.
   Do **not** filter `description:` — shape 7 names it as a defect site.

   A hit is a prompt to read the sentence, not a delete list. `This script costs
   more than the rest of the course` is a real cost warning and stays, and so is
   `the only thing that decides is the value the application put in the run
   context`.

3. Check the slots the greps cannot see: `Aside` titles, and the bold lead of a
   tip bullet. Both are heading slots in disguise and both follow the heading
   rule. Neither carries an anchor, so both are safe to change.

   ```bash
   grep -n 'title="[^"]*"' <file>        # Aside titles; ?" is shape 5
   grep -n '^- \*\*[^*]*\*\*:' <file>    # tip-bullet leads
   ```

4. Check the CLAUDE.md fixed terminology while you are here — nothing else does:

   ```bash
   grep -nEi '\b(ensure|verify|confirm|settings|config|options)\b' <file>
   ```

5. Delete any sentence whose only job is to tell the reader that the previous
   sentence was important.

6. **Re-wrap every paragraph you edited** to the wrap width already used in that
   file. The docs are mixed: tutorial lessons and the newer guide sections wrap
   at ~80, most guides and all provider pages use one line per paragraph. Match
   the region you are in. A ragged line is visible in the diff.

7. Before you rename a heading, make sure that no other page anchors to it, then
   build. `starlightLinksValidator` fails the build on a dead anchor:

   ```bash
   # every cross-page anchor in the docs, with the file and line that holds it
   grep -rno '/docs/[a-z0-9/_-]*#[a-z0-9-]*' docs/src/content/docs/

   # before renaming one heading, grep the slug it would break
   grep -rn '#the-run-context' docs/src/content/docs/

   cd docs && bun run build
   ```

   **A guide heading is not a tutorial heading.** Measured on this repo: 109
   cross-page anchors, and `guides/tools/#the-run-context` alone is linked from
   13 pages, while the whole `tutorial/` tree is the target of 2. A weak heading
   in a guide is usually worth keeping. Weigh the rename against the inbound
   links before you make it, and never rename a heading only because it reads
   better.

   If you are one of several passes running at once, **report the rename instead
   of making it** and let whoever owns the build decide.

## A changelog is not a page

`other/release-history.mdx` is a shipped record. Cut a sell line from an entry
(`More patterns and features coming soon!`) and fix a first-person aside, but do
not rewrite entries into better prose, and never touch a version number, a date
or a feature name. An old entry is allowed to read like its release.
