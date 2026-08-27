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
real sentence that shipped in the UC AI docs and was later cut. Most come from
the tutorial courses, because that is where the voice reviews happened, but the
shapes are not tutorial-specific and they turn up in guides too.

**1. The demonstrative recap.** Opens with `That is` / `This is` pointing back at
the block you just read, and names no new thing.

> ~~That is the control.~~ ~~That is the whole course in four rows.~~ ~~This is
> the whole idea of code mode.~~ ~~That is what the checks buy you.~~

Test: delete it. If no fact is lost, it was narrator. Often the fix is to fold
the noun into the next sentence: `That is the control. It holds whatever the user
types` becomes `The control holds whatever the user types`.

```bash
grep -nE '^(That|This) (is|was) ' <file>
```

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
grep -nE '\b(Read|Look at|Notice|Watch|See) (that|this|those|these|what|how|it|again)\b' <file>
```

**3. The pre-emptive defence.** A clause that insists your list or your design
choice was considered, without giving the reason.

> ~~Three details are not decoration:~~ ~~Each one earns its place.~~ ~~Three
> things changed, and all three are deliberate:~~

If a reason follows, keep the reason and drop the defence. `The commit is inside
the loop on purpose. One document is one unit of work, and a bad PDF at the end
of a run of a hundred must not undo the ninety-nine before it.` earns it — the
second sentence is the reason. `Three details are not decoration:` does not.

```bash
grep -nE '\b(not decoration|earns its place|deliberate|on purpose|not a strawman)\b' <file>
```

**4. The superlative closer.** Ends a block by ranking it instead of ending it.

> ~~the only honest way to know~~ ~~the only evidence that counts~~ ~~This is the
> check that matters~~ ~~A loud error is better than a number computed from
> nothing.~~ ~~the failure that looks most like success~~

```bash
grep -nE '\bthe only\b|\bmatters most\b|\bthe one that\b|\bbetter than\b' <file>
```

**5. Reader mind-reading.** Tells the reader what they expect, or what everybody
else does.

> ~~Everybody asks this, so the course measures it.~~ ~~This is the part people
> expect to break, and it does not.~~ ~~That surprises most people.~~ ~~Worth
> writing down, because it catches everybody once:~~

```bash
grep -nE '\beverybody\b|\bmost people\b|\bpeople expect\b|\bworth\b' <file>
```

**6. The importance trailer.** A clause appended to say the thing you just wrote
was important.

> ~~The consequence is important:~~ ~~and they are the whole point of the
> lesson~~ ~~and the reason is worth copying~~ ~~Two of those deserve
> attention:~~ ~~and each one tells you something~~

Original instances of these shapes, kept because they are the review that started
this list: "the model did nothing strange / is not wrong / the reasoning is good",
"this is the failure that matters", "that is what the rest of the course builds",
"that is the point of this lesson", "read that carefully", "now the honest part",
"two things that will surprise you", "nothing was invented", "quietly" used for
drama rather than a technical meaning, "now imagine writing the PL/SQL that...".

**7. The promise-line trailer**, a clause that sells the page instead of naming
its outcome. On a tutorial lesson this lives in the `promise=` prop, and an
em-dash inside that prop is nearly always the trailer:

```bash
grep -n 'promise="[^"]*—' <file>
```

The same defect appears in a reference page as a `description:` in the
frontmatter that advertises rather than describes.

A promise line names what the reader can do, in one clause, with no trailer:

- Bad: `a model answers a question about your own data — and you can see exactly
  where that approach stops.`
- Good: `call generate_text with contract rows in the prompt, then ask a
  question those rows cannot answer.`

## Self-check before you ship a page

1. Read only the headings, in order, as they appear in **On this page**. Each
   one must name a topic you could jump to. Rename any that comment.
2. Run the greps of all seven shapes above over the page:

   ```bash
   grep -nEi '^(That|This) (is|was) |\b(Read|Look at|Notice|Watch|See) (that|this|those|these|what|how|it|again)\b|\b(not decoration|earns its place|deliberate|on purpose)\b|\bthe only\b|\bmatters most\b|\bthe one that\b|\beverybody\b|\bmost people\b|\bworth\b|\bmatters\b|\bstrange\b|\bhonest|surprise|the point of|quietly|\bimagine\b' <file>
   ```

   Pipe through `| grep -vE ':(description|title):|title="Next lesson' | grep -v "^[^:]*:[0-9]*: *--"`
   to drop frontmatter, `LinkCard` props and SQL comments inside code blocks.
   Those are the bulk of the false positives.

   **On a reference page, expect shape 1 to be mostly noise.** Measured across
   `guides/`, `api/`, `providers/` and `other/`: 38 hits, and most of the
   `This is ...` ones introduce the code block that follows — `This is the same
   as the JSON {"name": "Alice"}`, `This is one uc_ai__run_code call.` Those are
   forward-pointing and they stay. The defect is a demonstrative pointing
   **back** at prose already read. A reference page is denser and has more code,
   so it earns more legitimate `This is` lines than a tutorial does.

   A hit is a prompt to read the sentence, not a delete list. `This script costs
   more than the rest of the course` is a real cost warning and stays, and so is
   `the only thing that decides is the value the application put in the run
   context`.

   Measured on the seven lessons of the second voice pass: this list returned 54
   lines, of which roughly 30 were real. The literal-phrase list it replaced
   returned 9 and missed every defect in four of the seven files. That is why
   this skill lists shapes and not phrases.
3. Delete any sentence whose only job is to tell the reader that the previous
   sentence was important.
4. **Re-wrap every paragraph you edited** to the roughly 80-column convention of
   the file. Cutting a clause out of the middle leaves a ragged line, and a
   ragged line is visible in the diff.
5. Before you rename a heading, make sure that no other page anchors to it, then
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

