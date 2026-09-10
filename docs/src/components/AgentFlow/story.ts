/**
 * Content and timing of the homepage animation.
 *
 * One refund request travels through an orchestrator and two specialist
 * agents. The orchestrator asks a model what to do, the specialists call the
 * reader's PL/SQL functions, and the functions read the reader's tables.
 *
 * Everything here is data. Every frame of the animation derives from a scene
 * index and the milliseconds elapsed inside that scene, so Previous, Next and
 * Replay can jump anywhere without state carried over from the last scene.
 *
 * Two ideas hold the file together:
 *
 * - A **beat** is one model call. It does not travel; the wire to the model
 *   glows, the model card says what it was given, and when the beat ends the
 *   agent card keeps what the model said. That makes a model call cheap
 *   enough to show all seven of them, which is what a real UC AI run makes.
 * - A **moment** is a scene plus milliseconds into it. Every "from when is
 *   this on screen" question is a moment, so nothing appears before the thing
 *   that causes it.
 *
 * All records and policy text are fictional demo content. Nothing calls a
 * model and nothing issues a refund.
 */

import type { Rect } from "./camera";

export type { Rect };

export type NodeKind =
  | "boundary"
  | "user"
  | "orchestrator"
  | "agent"
  | "tool"
  | "table"
  | "model"
  | "summary";

/** Colour role. Carries through an agent, its tools, its chips and its rows. */
export type Tone = "accent" | "billing" | "policy" | "neutral";

export interface StoryNode extends Rect {
  id: string;
  kind: NodeKind;
  title: string;
  subtitle?: string;
  tone: Tone;
  /** For a tool: the agent that owns it. For a table: the tool that reads it. */
  parent?: string;
  /**
   * The agent whose detail this node belongs to. Tools and tables exist only
   * while the camera is on their agent, which is what keeps a frame down to
   * about a dozen things to read.
   */
  detailOf?: string;
  /** Order in the opening reveal. */
  reveal: number;
  /**
   * The body of a tool, shown once the model has chosen it. Two lines of real
   * Oracle SQL with the argument already substituted, so a reader who knows
   * PL/SQL sees a function and not an API call.
   */
  sql?: string[];
  /** Columns of a table node. */
  columns?: string[];
  /**
   * Height of the card as a titled box: what an agent is until the run is
   * about its turn, and what every card falls back to in the far view, where
   * the canvas reads as a block diagram and the bodies are hidden anyway.
   */
  compactH?: number;
  /**
   * Height before the node's own content grows it. The conversation reserves
   * room for the answer only in the scene that has one, rather than standing
   * two thirds empty for the other seven.
   */
  collapsedH?: number;
}

/* ---------------------------------------------------------------- timing */

/** How long the camera takes to reach a new scene. */
export const CAMERA_MS = 800;
/** How long a chip takes to travel its wire. */
export const TRAVEL_MS = 700;
/** How long a chip rests on its landing point, then how long it fades. */
export const LINGER_MS = 500;
export const FADE_MS = 300;
/** Total life of a chip, from leaving to gone. */
export const CHIP_LIFE_MS = TRAVEL_MS + LINGER_MS + FADE_MS;
/** How long one model call takes. */
export const BEAT_MS = 1100;
/** A breath between two events in the same scene. */
export const GAP_MS = 200;
/** Milliseconds between node reveals in the opening scene. */
export const REVEAL_STAGGER_MS = 160;
/** Milliseconds between two rows landing in a table. */
export const ROW_STAGGER_MS = 160;
/** How long the session strip's counters take to run up. */
export const COUNT_MS = 600;

/**
 * Spacing between two chips on the same wire, wider than a chip's whole life
 * so that only one is ever moving.
 */
const CHIP_STEP_MS = CHIP_LIFE_MS + 100;

/*
 * The timeline of each scene that has more than one event, named so that a
 * moment further down can point at the same number the scene uses. Every
 * value is milliseconds after the camera arrives.
 */
const ORCH1 = { beat: 0, hand: BEAT_MS + GAP_MS };

const RUN = {
  query: 0,
  back: CHIP_STEP_MS,
  beat: CHIP_STEP_MS + CHIP_LIFE_MS + GAP_MS,
  report: CHIP_STEP_MS + CHIP_LIFE_MS + GAP_MS + BEAT_MS + GAP_MS,
};

const ORCH2 = { beat: 0, hand: BEAT_MS + GAP_MS };

const POLICY = {
  beat1: 0,
  query: BEAT_MS + GAP_MS,
  back: BEAT_MS + GAP_MS + CHIP_STEP_MS,
  beat2: BEAT_MS + GAP_MS + CHIP_STEP_MS + CHIP_LIFE_MS + GAP_MS,
  report:
    BEAT_MS + GAP_MS + CHIP_STEP_MS + CHIP_LIFE_MS + GAP_MS + BEAT_MS + GAP_MS,
};

const ANSWER = {
  beat: 0,
  hand: BEAT_MS + GAP_MS,
  /** Long enough to read the answer before the camera pulls back out. */
  pullOut: BEAT_MS + GAP_MS + TRAVEL_MS + 3000,
};

/* ----------------------------------------------------------------- canvas */

/*
 * Canvas units, 1600 x 900. Only the model sits outside the database
 * boundary: requests go out to it and decisions come back.
 *
 * An agent card carries `compactH`. Its full `h` is the open card, tall enough
 * for its tool rows, the tool the model opens, and the line the model leaves
 * behind. The chosen tool is placed last, so opening it grows into the card's
 * own padding instead of pushing the other rows down.
 */
export const NODES: StoryNode[] = [
  {
    id: "db",
    kind: "boundary",
    x: 30,
    y: 138,
    w: 1610,
    h: 745,
    title: "Your Oracle Database",
    subtitle: "UC AI",
    tone: "neutral",
    reveal: 0,
  },
  {
    id: "you",
    kind: "user",
    x: 70,
    y: 200,
    w: 250,
    h: 450,
    collapsedH: 240,
    compactH: 110,
    title: "You",
    tone: "accent",
    reveal: 1,
  },
  {
    id: "orch",
    kind: "orchestrator",
    x: 380,
    y: 200,
    w: 300,
    h: 220,
    compactH: 110,
    title: "Orchestrator",
    tone: "accent",
    reveal: 2,
  },
  {
    id: "billing",
    kind: "agent",
    x: 720,
    y: 168,
    w: 470,
    h: 315,
    compactH: 110,
    title: "Billing agent",
    tone: "billing",
    reveal: 3,
  },
  {
    id: "get_invoice",
    kind: "tool",
    x: 742,
    y: 232,
    w: 426,
    h: 38,
    title: "get_invoice",
    tone: "billing",
    parent: "billing",
    detailOf: "billing",
    reveal: 3,
  },
  {
    id: "issue_refund",
    kind: "tool",
    x: 742,
    y: 276,
    w: 426,
    h: 38,
    title: "issue_refund",
    tone: "billing",
    parent: "billing",
    detailOf: "billing",
    reveal: 3,
  },
  {
    id: "get_payments",
    kind: "tool",
    x: 742,
    y: 320,
    w: 426,
    h: 104,
    title: "get_payments",
    tone: "billing",
    parent: "billing",
    detailOf: "billing",
    reveal: 3,
    sql: [
      "select amount from payments",
      "where  invoice_id = 'INV-1003'",
    ],
  },
  {
    id: "payments",
    kind: "table",
    x: 1230,
    y: 168,
    w: 380,
    h: 230,
    title: "PAYMENTS",
    tone: "billing",
    parent: "get_payments",
    detailOf: "billing",
    reveal: 3,
    columns: ["INVOICE_ID", "AMOUNT"],
  },
  {
    id: "policy",
    kind: "agent",
    x: 720,
    y: 500,
    w: 470,
    h: 278,
    compactH: 110,
    title: "Policy agent",
    tone: "policy",
    reveal: 4,
  },
  {
    id: "get_customer_tier",
    kind: "tool",
    x: 742,
    y: 564,
    w: 426,
    h: 38,
    title: "get_customer_tier",
    tone: "policy",
    parent: "policy",
    detailOf: "policy",
    reveal: 4,
  },
  {
    id: "find_policy",
    kind: "tool",
    x: 742,
    y: 608,
    w: 426,
    h: 104,
    title: "find_policy",
    tone: "policy",
    parent: "policy",
    detailOf: "policy",
    reveal: 4,
    sql: [
      "select rule_text from refund_policies",
      "where  reason_code = 'duplicate_payment'",
    ],
  },
  {
    id: "policies",
    kind: "table",
    x: 1230,
    y: 500,
    w: 380,
    h: 230,
    title: "REFUND_POLICIES",
    tone: "policy",
    parent: "find_policy",
    detailOf: "policy",
    reveal: 4,
    columns: ["REASON_CODE", "RULE_TEXT"],
  },
  {
    id: "model",
    kind: "model",
    x: 340,
    y: 16,
    w: 460,
    h: 110,
    title: "AI model",
    tone: "accent",
    reveal: 5,
  },
  {
    id: "summary",
    kind: "summary",
    x: 70,
    y: 800,
    w: 1500,
    h: 70,
    title: "Session",
    tone: "neutral",
    reveal: 6,
  },
];

export const NODE_BY_ID: Record<string, StoryNode> = Object.fromEntries(
  NODES.map((node) => [node.id, node]),
);

/** Nodes that exist at level 0, which is what the opening reveal counts. */
export const LEVEL0_COUNT = NODES.filter((node) => !node.detailOf).length;

/** The boundary is structure, not a story beat, so it is never dimmed. */
export const ALWAYS_LIT = new Set(["db"]);

export interface Wire {
  from: string;
  to: string;
}

/*
 * A wire exists where work actually flows in this run. Every agent has a wire
 * to the model, because every agent is its own model loop. The three tools the
 * model does not choose have no wire, which is the point: they are available,
 * and this request did not need them.
 */
export const WIRES: Wire[] = [
  { from: "you", to: "orch" },
  { from: "orch", to: "model" },
  { from: "orch", to: "billing" },
  { from: "orch", to: "policy" },
  { from: "billing", to: "model" },
  { from: "policy", to: "model" },
  { from: "get_payments", to: "payments" },
  { from: "find_policy", to: "policies" },
];

export const wireKey = (from: string, to: string) => `${from}-${to}`;

/* ------------------------------------------------------------------ story */

export const PROMPT =
  "I was charged twice for invoice INV-1003. Can I get a refund?";

export const FINAL_ANSWER =
  "You paid €49 twice for INV-1003. The extra €49 qualifies for a refund.";

export const ANSWER_SOURCES = ["PAYMENTS", "REFUND_POLICIES"];

export const CLOSING =
  "Your agents work together. UC AI connects them to your PL/SQL tools and business data.";

/** A row of demo data. `cells` lines up with the table node's `columns`. */
export interface DataRow {
  cells: string[];
  /** Rows the where clause selects get the tone background. */
  match?: boolean;
}

export const PAYMENT_ROWS: DataRow[] = [
  { cells: ["INV-0977", "€120"] },
  { cells: ["INV-1003", "€49"], match: true },
  { cells: ["INV-1003", "€49"], match: true },
];

export const POLICY_ROWS: DataRow[] = [
  { cells: ["duplicate_payment", "Refund extra"], match: true },
  { cells: ["service_downgrade", "Pro-rate"] },
];

export const ROWS_BY_TABLE: Record<string, DataRow[]> = {
  payments: PAYMENT_ROWS,
  policies: POLICY_ROWS,
};

export const POLICY_RULE =
  "Duplicate payment: refund the extra payment to the original payment method.";

/* ---------------------------------------------------------- the provider */

export interface Provider {
  /** How the provider is named in prose. */
  name: string;
  /** A model id UC AI accepts for that provider, verbatim. */
  model: string;
}

/*
 * The model card names one real provider and one real model of that provider,
 * and shows a different pair on every visit and every replay. The point the
 * picture has to make is that the box outside the database is interchangeable,
 * and a concrete name makes that better than the word "any" does.
 *
 * Every model id here is a constant from the matching provider package.
 */
export const PROVIDERS: Provider[] = [
  { name: "Anthropic", model: "claude-opus-5" },
  { name: "OpenAI", model: "gpt-6-astra" },
  { name: "Google", model: "gemini-3.8-flash" },
  { name: "xAI", model: "grok-4.6" },
  { name: "Mistral", model: "mistral-large-latest" },
  { name: "Ollama", model: "qwen3:8b" },
  { name: "OCI", model: "meta.llama-3.3-70b-instruct" },
  { name: "OpenRouter", model: "anthropic/claude-sonnet-5" },
];

export const providerLabel = (provider: Provider) =>
  `${provider.name} · ${provider.model}`;

/** A provider other than the one on screen, so a replay always changes it. */
export function otherProvider(current: number): number {
  const step = 1 + Math.floor(Math.random() * (PROVIDERS.length - 1));
  return (current + step) % PROVIDERS.length;
}

/* -------------------------------------------------------------- moments */

/** A point in the run: a scene, and milliseconds after its camera arrives. */
export interface Moment {
  scene: number;
  at: number;
}

/**
 * Whether the run has passed a moment.
 *
 * @param motion milliseconds since the scene's camera arrived. A scene reached
 *   by hand passes `Infinity`, so every end state is exact.
 */
export function reached(moment: Moment, index: number, motion: number): boolean {
  if (index !== moment.scene) {
    return index > moment.scene;
  }
  return motion >= moment.at;
}

/*
 * Scene indices, named. Every "from when" below points at the event that
 * causes it rather than at the start of a scene, so nothing on a card can
 * appear before the chip or the model call that put it there.
 */
const S_SYSTEM = 0;
const S_REQUEST = 1;
const S_ORCH1 = 2;
const S_CHOOSE = 3;
const S_RUN = 4;
const S_ORCH2 = 5;
const S_POLICY = 6;
const S_ANSWER = 7;

export const MOMENTS = {
  /** The plan card, written when the model answers the first question. */
  plan: { scene: S_ORCH1, at: ORCH1.beat + BEAT_MS },
  /** The tool the model picks, opening with the SQL it runs. */
  getPayments: { scene: S_CHOOSE, at: BEAT_MS },
  findPolicy: { scene: S_POLICY, at: POLICY.beat1 + BEAT_MS },
  /** A table appears with the tool that is about to read it. */
  paymentsShown: { scene: S_RUN, at: 0 },
  policiesShown: { scene: S_POLICY, at: POLICY.beat1 + BEAT_MS },
  /** Rows land when the query chip reaches the table. */
  paymentsRows: { scene: S_RUN, at: RUN.query + TRAVEL_MS },
  policiesRows: { scene: S_POLICY, at: POLICY.query + TRAVEL_MS },
  /** A plan line ticks when the specialist's result reaches the orchestrator. */
  tick1: { scene: S_RUN, at: RUN.report + TRAVEL_MS },
  tick2: { scene: S_POLICY, at: POLICY.report + TRAVEL_MS },
  /** The answer bubble, and the conversation card growing to hold it. */
  answer: { scene: S_ANSWER, at: ANSWER.hand + TRAVEL_MS },
  /** The session strip, once the camera has pulled back out. */
  summary: { scene: S_ANSWER, at: ANSWER.pullOut + CAMERA_MS },
} satisfies Record<string, Moment>;

/* ------------------------------------------------------------- the scenes */

export type TransferKind = "task" | "result";

export interface Transfer {
  from: string;
  to: string;
  kind: TransferKind;
  label: string;
  /** Milliseconds after the camera arrives. */
  at: number;
}

/**
 * One model call.
 *
 * A beat does not travel. The wire from the agent to the model glows for its
 * length, the model card says what it was given, and when it ends `yields`
 * stays on the agent card. That is a whole model round trip in 1.1 seconds,
 * which is what makes it affordable to show every one of them.
 */
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

export interface Scene {
  id: string;
  title: string;
  caption: string;
  /** Set when the caption is a message rather than narration. */
  quote?: boolean;
  /** Nodes to frame. An empty list frames the whole canvas. */
  frame: string[];
  /**
   * Frame for a narrow viewport. Two nodes half the canvas apart cap the zoom
   * at about 0.5 on a phone, which leaves the labels too small, so a phone
   * follows the focus one card at a time and lets a chip arrive from off frame.
   */
  frameNarrow?: string[];
  framePadding?: number;
  /** A second camera target inside the same scene. */
  frameThen?: string[];
  frameThenAt?: number;
  /** Caption to show once the second camera target is reached. */
  captionThen?: string;
  /** Nodes drawn at full strength. Every other node is dimmed. */
  lit: string[];
  /**
   * The agent whose card is open in this scene. Its tool rows and its table
   * exist only here; every other agent stays a titled box.
   */
  detail?: string;
  transfers: Transfer[];
  beats: Beat[];
  /**
   * Milliseconds to hold after the last movement ends. A hold is for reading
   * what just changed: long after a scene reveals the SQL or the answer, short
   * after a chip that has already landed and faded.
   */
  hold: number;
}

export const SCENES: Scene[] = [
  {
    id: "system",
    title: "The system",
    caption: "Everything here runs in your Oracle database. Except the model.",
    frame: [],
    lit: ["you", "orch", "billing", "policy", "model"],
    transfers: [],
    beats: [],
    /*
     * Shorter than it looks. The reveal here runs from the scene's own start
     * rather than from the camera arriving, so this hold begins about 800ms
     * earlier than the same number would in any other scene.
     */
    hold: 1700,
  },
  {
    id: "request",
    title: "The request",
    caption: PROMPT,
    quote: true,
    frame: ["you", "orch"],
    framePadding: 30,
    frameNarrow: ["orch"],
    lit: ["you", "orch"],
    transfers: [
      {
        from: "you",
        to: "orch",
        kind: "task",
        label: "Refund request · INV-1003",
        at: 0,
      },
    ],
    beats: [],
    hold: 1200,
  },
  {
    id: "orch1",
    title: "The orchestrator thinks",
    caption: "The orchestrator asks the model what to do first.",
    frame: ["orch", "model"],
    frameNarrow: ["model"],
    lit: ["orch", "model"],
    beats: [
      {
        agent: "orch",
        at: ORCH1.beat,
        given: "the question",
        yields: "Ask Billing first",
      },
    ],
    transfers: [
      {
        from: "orch",
        to: "billing",
        kind: "task",
        label: "Check payments · INV-1003",
        at: ORCH1.hand,
      },
    ],
    hold: 800,
  },
  {
    id: "choose",
    title: "Choose a tool",
    caption: "The model does not run code. It picks one of your functions.",
    frame: ["billing", "model"],
    frameNarrow: ["billing"],
    lit: ["billing", "model", "get_payments", "get_invoice", "issue_refund"],
    detail: "billing",
    beats: [{ agent: "billing", at: 0, given: "the task" }],
    transfers: [],
    hold: 3500,
  },
  {
    id: "run",
    title: "Your function runs",
    caption: "UC AI runs get_payments. Your SQL, your table, your rows.",
    frame: ["billing", "payments"],
    frameNarrow: ["payments"],
    lit: ["billing", "get_payments", "payments"],
    detail: "billing",
    transfers: [
      {
        from: "get_payments",
        to: "payments",
        kind: "task",
        label: "invoice_id = 'INV-1003'",
        at: RUN.query,
      },
      {
        from: "payments",
        to: "get_payments",
        kind: "result",
        label: "2 rows",
        at: RUN.back,
      },
      {
        from: "billing",
        to: "orch",
        kind: "result",
        label: "2 payments · €49",
        at: RUN.report,
      },
    ],
    beats: [
      {
        agent: "billing",
        at: RUN.beat,
        given: "the rows",
        yields: "2 × €49 · a duplicate",
      },
    ],
    hold: 1200,
  },
  {
    id: "orch2",
    title: "The orchestrator thinks again",
    caption: "The orchestrator asks the model what is next.",
    frame: ["orch", "model"],
    frameNarrow: ["model"],
    lit: ["orch", "model"],
    beats: [
      {
        agent: "orch",
        at: ORCH2.beat,
        given: "Billing's answer",
        yields: "Ask Policy next",
      },
    ],
    transfers: [
      {
        from: "orch",
        to: "policy",
        kind: "task",
        label: "Find refund rule",
        at: ORCH2.hand,
      },
    ],
    hold: 800,
  },
  {
    id: "policy",
    title: "The second specialist",
    caption: "The Policy agent does the same with find_policy.",
    frame: ["policy", "policies"],
    frameNarrow: ["policies"],
    lit: ["policy", "find_policy", "get_customer_tier", "policies", "model"],
    detail: "policy",
    beats: [
      { agent: "policy", at: POLICY.beat1, given: "the task" },
      {
        agent: "policy",
        at: POLICY.beat2,
        given: "the row",
        yields: "Refund the extra payment",
      },
    ],
    transfers: [
      {
        from: "find_policy",
        to: "policies",
        kind: "task",
        label: "duplicate_payment",
        at: POLICY.query,
      },
      {
        from: "policies",
        to: "find_policy",
        kind: "result",
        label: "1 row",
        at: POLICY.back,
      },
      {
        from: "policy",
        to: "orch",
        kind: "result",
        label: "Refund extra payment",
        at: POLICY.report,
      },
    ],
    hold: 1500,
  },
  {
    id: "answer",
    title: "The answer",
    caption: FINAL_ANSWER,
    quote: true,
    frame: ["you", "orch"],
    framePadding: 30,
    frameNarrow: ["you"],
    frameThen: [],
    frameThenAt: ANSWER.pullOut,
    captionThen: CLOSING,
    lit: ["you", "orch", "billing", "policy", "model", "summary"],
    beats: [
      {
        agent: "orch",
        at: ANSWER.beat,
        given: "both answers",
        yields: "Answer ready",
      },
    ],
    transfers: [
      {
        from: "orch",
        to: "you",
        kind: "result",
        label: "Answer ready",
        at: ANSWER.hand,
      },
    ],
    hold: 2500,
  },
];

export const LAST = SCENES.length - 1;

/* --------------------------------------------------------- run statistics */

/** Counted from the scenes, so the closing strip cannot drift from the story. */
export const MODEL_CALLS = SCENES.reduce(
  (total, scene) => total + scene.beats.length,
  0,
);

export const TOOL_CALLS = SCENES.reduce(
  (total, scene) =>
    total +
    scene.transfers.filter(
      (transfer) => NODE_BY_ID[transfer.to]?.kind === "table",
    ).length,
  0,
);

export const SESSION_STATS = [
  { value: 3, label: "agents" },
  { value: MODEL_CALLS, label: "model calls" },
  { value: TOOL_CALLS, label: "function calls" },
  { value: 1, label: "session" },
];

/* ----------------------------------------------------------- scene length */

/**
 * Milliseconds from the camera arriving to the last thing on screen settling.
 * A scene must not advance while a chip is still fading out or a beat is
 * still running.
 */
export function movementEnd(scene: Scene): number {
  const lastChip = scene.transfers.reduce(
    (latest, transfer) => Math.max(latest, transfer.at + CHIP_LIFE_MS),
    0,
  );
  const lastBeat = scene.beats.reduce(
    (latest, beat) => Math.max(latest, beat.at + BEAT_MS),
    0,
  );
  const revealDone =
    scene.id === "system" ? LEVEL0_COUNT * REVEAL_STAGGER_MS : 0;
  /*
   * The pull-out is not finished when the camera arrives: the session strip
   * counts up afterwards. Leaving that out stopped the clock one frame before
   * the counters started, so they stood at zero.
   */
  const secondCamera =
    scene.frameThenAt === undefined
      ? 0
      : scene.frameThenAt + CAMERA_MS + COUNT_MS;

  return Math.max(lastChip, lastBeat, revealDone, secondCamera);
}

/** Milliseconds the whole scene takes, camera plus movement plus hold. */
export function durationOf(scene: Scene): number {
  return CAMERA_MS + movementEnd(scene) + scene.hold;
}

export const TOTAL_MS = SCENES.reduce(
  (total, scene) => total + durationOf(scene),
  0,
);

/* -------------------------------------------------------- derived state */

/**
 * A node's height in a given scene, which the camera has to agree with.
 *
 * This takes the scene index and not the clock, so the camera for a scene is
 * the same rectangle from its first frame to its last. A card that grows
 * inside a scene grows into space the camera already framed, rather than
 * moving the camera while it grows.
 */
export function heightAt(node: StoryNode, index: number): number {
  if (node.kind === "agent") {
    return SCENES[index]?.detail === node.id ? node.h : (node.compactH ?? node.h);
  }
  if (node.collapsedH !== undefined) {
    return index >= MOMENTS.answer.scene ? node.h : node.collapsedH;
  }
  return node.h;
}

/**
 * A node's height as it is actually drawn right now.
 *
 * This is the clock-aware twin of `heightAt`. The camera uses the grown height
 * from the scene's first frame, so it does not move while the card grows; the
 * card itself waits for the chip that fills it.
 *
 * @param far true when the camera is far enough out that the canvas reads as a
 *   block diagram. Every card body is hidden there, so a card that keeps its
 *   near-view height would stand as a tall empty box.
 */
export function renderHeightAt(
  node: StoryNode,
  index: number,
  motion: number,
  far = false,
): number {
  if (far && node.compactH !== undefined) {
    return node.compactH;
  }
  if (node.collapsedH !== undefined) {
    return reached(MOMENTS.answer, index, motion) ? node.h : node.collapsedH;
  }
  return heightAt(node, index);
}

/**
 * The top edge of a card of a given height.
 *
 * An agent card is anchored by its foot: its `y` is where the open card
 * starts, so a compact card sits at the bottom of that space and unfolds
 * upward. Two things come out of that. The level-0 diagram is evenly spread
 * instead of leaving a third of the database box empty below the compact
 * cards, and a card that opens grows into room the camera already framed.
 */
function topFor(node: StoryNode, h: number): number {
  return node.kind === "agent" ? node.y + node.h - h : node.y;
}

/** The rect a node occupies in a given scene. What the camera frames. */
export function rectAt(node: StoryNode, index: number): Rect {
  const h = heightAt(node, index);
  return { x: node.x, y: topFor(node, h), w: node.w, h };
}

/** The rect a node is actually drawn at right now. */
export function renderRectAt(
  node: StoryNode,
  index: number,
  motion: number,
  far = false,
): Rect {
  const h = renderHeightAt(node, index, motion, far);
  return { x: node.x, y: topFor(node, h), w: node.w, h };
}

export function rectsFor(ids: string[], index = LAST): Rect[] {
  return ids
    .map((id) => NODE_BY_ID[id])
    .filter(Boolean)
    .map((node) => rectAt(node, index));
}

/** Where a table first appears. It arrives with the tool that reads it. */
const TABLE_SHOWN: Record<string, Moment> = {
  payments: MOMENTS.paymentsShown,
  policies: MOMENTS.policiesShown,
};

/** Where a table's rows land. */
const TABLE_ROWS: Record<string, Moment> = {
  payments: MOMENTS.paymentsRows,
  policies: MOMENTS.policiesRows,
};

/** Where a tool opens with its SQL. */
const TOOL_CHOSEN: Record<string, Moment> = {
  get_payments: MOMENTS.getPayments,
  find_policy: MOMENTS.findPolicy,
};

/**
 * Whether a node is on the canvas at all.
 *
 * Detail exists only where the camera is. A map shows street names when you
 * zoom in; the same rule here is what takes a frame from 35 things to read
 * down to about a dozen.
 */
export function visibleAt(
  node: StoryNode,
  index: number,
  motion: number,
): boolean {
  const scene = SCENES[index];

  if (node.kind === "summary") {
    return reached(MOMENTS.summary, index, motion);
  }

  if (node.detailOf) {
    if (scene?.detail !== node.detailOf) {
      return false;
    }
    const shown = TABLE_SHOWN[node.id];
    return shown === undefined || reached(shown, index, motion);
  }

  return true;
}

export const planVisibleAt = (index: number, motion: number) =>
  reached(MOMENTS.plan, index, motion);

export const PLAN_ITEMS = [
  { label: "Check the payments", done: MOMENTS.tick1 },
  { label: "Check the refund rule", done: MOMENTS.tick2 },
];

export function planAt(index: number, motion: number) {
  return PLAN_ITEMS.map((item) => ({
    label: item.label,
    done: reached(item.done, index, motion),
    /** True on the scene where the tick appears, so it can pop once. */
    justDone: index === item.done.scene,
  }));
}

/**
 * The last thing the model told this agent, at this point in the run.
 *
 * A chip is a messenger and fades, and a beat does not travel at all, so what
 * the model said has to land somewhere. This is where it lands: one line on
 * the agent's own card, replaced each time the model answers again.
 */
export function noteFor(
  agent: string,
  index: number,
  motion: number,
): string | undefined {
  let text: string | undefined;

  for (let scene = 0; scene <= index && scene < SCENES.length; scene += 1) {
    for (const beat of SCENES[scene].beats) {
      if (beat.agent !== agent || !beat.yields) {
        continue;
      }
      if (reached({ scene, at: beat.at + BEAT_MS }, index, motion)) {
        text = beat.yields;
      }
    }
  }

  return text;
}

/** The beat running right now, if any. */
export function beatAt(index: number, motion: number): Beat | undefined {
  return SCENES[index]?.beats.find(
    (beat) => motion >= beat.at && motion < beat.at + BEAT_MS,
  );
}

export function toolChosenAt(
  toolId: string,
  index: number,
  motion: number,
): boolean {
  const moment = TOOL_CHOSEN[toolId];
  return moment !== undefined && reached(moment, index, motion);
}

/** A tool the model passed over, once the choice has been made. */
export function toolPassedAt(
  toolId: string,
  index: number,
  motion: number,
): boolean {
  const node = NODE_BY_ID[toolId];
  if (!node?.parent) {
    return false;
  }
  const siblingChosen = NODES.some(
    (other) =>
      other.parent === node.parent &&
      other.id !== toolId &&
      toolChosenAt(other.id, index, motion),
  );
  return siblingChosen && !toolChosenAt(toolId, index, motion);
}

/** How many rows of a table have landed. */
export function rowsShownAt(
  tableId: string,
  index: number,
  motion: number,
  total: number,
): number {
  const moment = TABLE_ROWS[tableId];
  if (!moment) {
    return 0;
  }
  if (index !== moment.scene) {
    return index > moment.scene ? total : 0;
  }
  if (motion < moment.at) {
    return 0;
  }
  return Math.min(total, Math.floor((motion - moment.at) / ROW_STAGGER_MS) + 1);
}

export const answerVisibleAt = (index: number, motion: number) =>
  reached(MOMENTS.answer, index, motion);

export const summaryVisibleAt = (index: number, motion: number) =>
  reached(MOMENTS.summary, index, motion);
