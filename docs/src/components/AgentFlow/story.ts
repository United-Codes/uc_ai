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
 * All records and policy text are fictional demo content. Nothing calls a
 * model and nothing issues a refund.
 */

import type { Rect } from "./camera";

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
  /** Order in the scene 0 reveal. */
  reveal: number;
  /**
   * The body of a tool, shown once the model has chosen it. Three lines of
   * real Oracle SQL with a bind variable, so a reader who knows PL/SQL sees a
   * function and not an API call.
   */
  sql?: string[];
  /** The argument the model passed, which is what its decision chip carried. */
  bind?: string;
  /** Columns of a table node. */
  columns?: string[];
}

/* ----------------------------------------------------------------- canvas */

/*
 * Canvas units, 1600 x 900. Only the model sits outside the database
 * boundary: requests go out to it and decisions come back.
 */
export const NODES: StoryNode[] = [
  {
    id: "model",
    kind: "model",
    x: 340,
    y: 16,
    w: 460,
    h: 110,
    title: "AI model",
    subtitle: "Claude, GPT, Gemini, or a local Ollama model",
    tone: "accent",
    reveal: 11,
  },
  {
    id: "db",
    kind: "boundary",
    x: 40,
    y: 138,
    w: 1540,
    h: 748,
    title: "Oracle Database",
    subtitle: "UC AI",
    tone: "neutral",
    reveal: 0,
  },
  {
    id: "you",
    kind: "user",
    x: 80,
    y: 210,
    w: 230,
    h: 400,
    title: "You",
    subtitle: "APEX · PL/SQL",
    tone: "accent",
    reveal: 1,
  },
  {
    id: "orch",
    kind: "orchestrator",
    x: 350,
    y: 210,
    w: 290,
    h: 250,
    title: "Orchestrator",
    subtitle: "Plans the run",
    tone: "accent",
    reveal: 2,
  },
  {
    id: "billing",
    kind: "agent",
    x: 700,
    y: 150,
    w: 420,
    h: 340,
    title: "Billing agent",
    subtitle: "Finds the payment facts",
    tone: "billing",
    reveal: 3,
  },
  {
    id: "get_invoice",
    kind: "tool",
    x: 722,
    y: 240,
    w: 376,
    h: 36,
    title: "get_invoice",
    tone: "billing",
    parent: "billing",
    reveal: 4,
  },
  {
    id: "issue_refund",
    kind: "tool",
    x: 722,
    y: 282,
    w: 376,
    h: 36,
    title: "issue_refund",
    tone: "billing",
    parent: "billing",
    reveal: 4,
  },
  {
    id: "get_payments",
    kind: "tool",
    x: 722,
    y: 324,
    w: 376,
    h: 144,
    title: "get_payments",
    tone: "billing",
    parent: "billing",
    reveal: 4,
    sql: [
      "select invoice_id, amount, status",
      "from   payments",
      "where  invoice_id = :p_invoice",
    ],
    bind: "p_invoice => 'INV-1003'",
  },
  {
    id: "payments",
    kind: "table",
    x: 1180,
    y: 170,
    w: 380,
    h: 230,
    title: "PAYMENTS",
    tone: "billing",
    parent: "get_payments",
    reveal: 5,
    columns: ["INVOICE_ID", "AMOUNT", "STATUS"],
  },
  {
    id: "policy",
    kind: "agent",
    x: 700,
    y: 500,
    w: 420,
    h: 300,
    title: "Policy agent",
    subtitle: "Finds the refund rule",
    tone: "policy",
    reveal: 6,
  },
  {
    id: "get_customer_tier",
    kind: "tool",
    x: 722,
    y: 592,
    w: 376,
    h: 36,
    title: "get_customer_tier",
    tone: "policy",
    parent: "policy",
    reveal: 7,
  },
  {
    id: "find_policy",
    kind: "tool",
    x: 722,
    y: 634,
    w: 376,
    h: 144,
    title: "find_policy",
    tone: "policy",
    parent: "policy",
    reveal: 7,
    sql: [
      "select rule_text",
      "from   refund_policies",
      "where  reason_code = :p_reason",
    ],
    bind: "p_reason => 'duplicate_payment'",
  },
  {
    id: "policies",
    kind: "table",
    x: 1180,
    y: 520,
    w: 380,
    h: 230,
    title: "REFUND_POLICIES",
    tone: "policy",
    parent: "find_policy",
    reveal: 8,
    columns: ["REASON_CODE", "RULE_TEXT"],
  },
  {
    id: "summary",
    kind: "summary",
    x: 80,
    y: 810,
    w: 1420,
    h: 66,
    title: "Session",
    tone: "neutral",
    reveal: 10,
  },
];

export const NODE_BY_ID: Record<string, StoryNode> = Object.fromEntries(
  NODES.map((node) => [node.id, node]),
);

export function rectsFor(ids: string[]): Rect[] {
  return ids.map((id) => NODE_BY_ID[id]).filter(Boolean);
}

/** The boundary and the session strip are structure, not story beats. */
export const ALWAYS_LIT = new Set(["db"]);

export interface Wire {
  from: string;
  to: string;
}

/*
 * A wire exists where work actually flows in this run. The three tools the
 * model does not choose have no wire, which is the point: they are available,
 * and this request did not need them.
 */
export const WIRES: Wire[] = [
  { from: "you", to: "orch" },
  { from: "orch", to: "model" },
  { from: "orch", to: "billing" },
  { from: "orch", to: "policy" },
  { from: "billing", to: "model" },
  { from: "get_payments", to: "payments" },
  { from: "find_policy", to: "policies" },
];

/* ------------------------------------------------------------------ story */

export const PROMPT =
  "I was charged twice for invoice INV-1003. Can I get a refund?";

export const FINAL_ANSWER =
  "You paid €49 twice for invoice INV-1003. Under the refund policy, the extra €49 qualifies for a refund.";

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
  { cells: ["INV-0977", "€120", "Completed"] },
  { cells: ["INV-1003", "€49", "Completed"], match: true },
  { cells: ["INV-1003", "€49", "Completed"], match: true },
];

export const POLICY_ROWS: DataRow[] = [
  {
    cells: ["duplicate_payment", "Refund extra payment"],
    match: true,
  },
  { cells: ["service_downgrade", "Pro-rate difference"] },
];

export const ROWS_BY_TABLE: Record<string, DataRow[]> = {
  payments: PAYMENT_ROWS,
  policies: POLICY_ROWS,
};

export const POLICY_RULE =
  "Duplicate payment: refund the extra payment to the original payment method.";

export const PLAN_ITEMS = [
  { label: "Check the payments", doneAt: 6 },
  { label: "Check the refund rule", doneAt: 8 },
];

/*
 * The orchestrator's latest decision, kept on its card. A chip is a messenger
 * and fades, so anything a decision chip says has to land somewhere; this is
 * where the model's answers land.
 */
export const PLAN_NOTES = [
  { from: 2, text: "Payments first, then the refund rule" },
  { from: 6, text: "A duplicate. Ask Policy about refunds" },
  { from: 8, text: "Both findings in. Write the answer" },
];

export function planNoteAt(index: number): string | undefined {
  let note: string | undefined;
  for (const entry of PLAN_NOTES) {
    if (index >= entry.from) {
      note = entry.text;
    }
  }
  return note;
}

export const SESSION_STATS = [
  { value: 3, label: "agents" },
  { value: 2, label: "tool calls" },
  { value: 4, label: "model calls" },
  { value: 1, label: "session" },
];

export type TransferKind = "task" | "result" | "ask" | "decision";

export interface Transfer {
  from: string;
  to: string;
  kind: TransferKind;
  label: string;
  /** Milliseconds after the camera arrives. */
  at: number;
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
   * A second line on the model card. This is where the picture says what the
   * model does and does not do.
   */
  modelNote?: string;
  transfers: Transfer[];
  /** Milliseconds to hold after the last movement ends. */
  hold: number;
}

/** How long the camera takes to reach a new scene. */
export const CAMERA_MS = 800;
/** How long a chip takes to travel its wire. */
export const TRAVEL_MS = 700;
/** How long the model shows its thinking dots. */
export const THINK_MS = 600;
/** How long a chip rests on its landing point, then how long it fades. */
export const LINGER_MS = 200;
export const FADE_MS = 250;
/** Total life of a chip, from leaving to gone. */
export const CHIP_LIFE_MS = TRAVEL_MS + LINGER_MS + FADE_MS;
/** Milliseconds between node reveals in the opening scene. */
export const REVEAL_STAGGER_MS = 60;

export const SCENES: Scene[] = [
  {
    id: "system",
    title: "The system",
    caption:
      "Everything here lives in your Oracle database, except the AI model. You ask one question.",
    frame: [],
    lit: ["you"],
    transfers: [],
    hold: 1600,
  },
  {
    id: "request",
    title: "The request",
    caption: PROMPT,
    quote: true,
    frame: ["you", "orch"],
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
    hold: 1000,
  },
  {
    id: "plan",
    title: "The plan",
    caption:
      "The orchestrator asks the model what to do. The model plans; your PL/SQL runs.",
    frame: ["orch", "model"],
    frameNarrow: ["model"],
    lit: ["orch", "model"],
    transfers: [
      {
        from: "orch",
        to: "model",
        kind: "ask",
        label: "What should we check?",
        at: 0,
      },
      {
        from: "model",
        to: "orch",
        kind: "decision",
        label: "Payments first, then the refund rule",
        at: 1250,
      },
    ],
    hold: 1000,
  },
  {
    id: "delegate",
    title: "Delegate",
    caption: "First the payments. That is the Billing agent's job.",
    frame: ["orch", "billing"],
    frameNarrow: ["billing"],
    lit: ["orch", "billing"],
    transfers: [
      {
        from: "orch",
        to: "billing",
        kind: "task",
        label: "Check the payments for INV-1003",
        at: 0,
      },
    ],
    hold: 1000,
  },
  {
    id: "choose",
    title: "Choose a tool",
    caption:
      "The model does not run code. It picks one of your functions and its arguments.",
    frame: ["billing", "model"],
    frameNarrow: ["billing"],
    lit: ["billing", "model", "get_payments", "get_invoice", "issue_refund"],
    modelNote: "returns a function name and its arguments",
    transfers: [
      {
        from: "billing",
        to: "model",
        kind: "ask",
        label: "Which tool?",
        at: 0,
      },
      {
        from: "model",
        to: "billing",
        kind: "decision",
        label: "get_payments('INV-1003')",
        at: 1250,
      },
    ],
    hold: 1000,
  },
  {
    id: "read",
    title: "Read your data",
    caption:
      "UC AI calls get_payments. Your PL/SQL runs the SQL on your own table.",
    frame: ["billing", "payments"],
    frameNarrow: ["payments"],
    lit: ["billing", "get_payments", "payments"],
    transfers: [
      {
        from: "get_payments",
        to: "payments",
        kind: "task",
        label: "invoice_id = 'INV-1003'",
        at: 0,
      },
      {
        from: "payments",
        to: "get_payments",
        kind: "result",
        label: "2 rows → JSON",
        at: 1250,
      },
    ],
    hold: 1800,
  },
  {
    id: "report",
    title: "Report back",
    caption: "Two completed payments of €49 for the same invoice.",
    frame: ["orch", "billing", "model"],
    frameNarrow: ["orch"],
    lit: ["orch", "billing", "model", "get_payments"],
    transfers: [
      {
        from: "billing",
        to: "orch",
        kind: "result",
        label: "2 payments · €49 each",
        at: 0,
      },
      { from: "orch", to: "model", kind: "ask", label: "What next?", at: 1250 },
      {
        from: "model",
        to: "orch",
        kind: "decision",
        label: "A duplicate. Ask Policy",
        at: 2500,
      },
    ],
    hold: 900,
  },
  {
    id: "second",
    title: "Second specialist",
    caption:
      "UC AI calls find_policy. The same again: your function, your table.",
    frame: ["policy", "policies"],
    frameNarrow: ["policies"],
    framePadding: 90,
    lit: ["policy", "find_policy", "policies"],
    transfers: [
      {
        from: "orch",
        to: "policy",
        kind: "task",
        label: "Find the refund rule",
        at: 0,
      },
      {
        from: "find_policy",
        to: "policies",
        kind: "task",
        label: "reason_code = 'duplicate_payment'",
        at: 1250,
      },
      {
        from: "policies",
        to: "find_policy",
        kind: "result",
        label: "1 row → JSON",
        at: 2500,
      },
    ],
    hold: 1400,
  },
  {
    id: "combine",
    title: "Combine",
    caption:
      "The orchestrator has the facts and the rule. It writes the answer.",
    frame: ["orch", "model"],
    frameNarrow: ["orch"],
    lit: ["orch", "model"],
    transfers: [
      {
        from: "policy",
        to: "orch",
        kind: "result",
        label: "Refund the extra payment",
        at: 0,
      },
      {
        from: "orch",
        to: "model",
        kind: "ask",
        label: "Compose the answer",
        at: 1250,
      },
      {
        from: "model",
        to: "orch",
        kind: "decision",
        label: "Answer ready",
        at: 2500,
      },
    ],
    hold: 900,
  },
  {
    id: "answer",
    title: "The answer",
    caption: FINAL_ANSWER,
    quote: true,
    frame: ["you", "orch"],
    frameNarrow: ["you"],
    frameThen: [],
    frameThenAt: 2000,
    captionThen: CLOSING,
    lit: NODES.map((node) => node.id),
    transfers: [
      { from: "orch", to: "you", kind: "result", label: "Answer ready", at: 0 },
    ],
    hold: 2000,
  },
];

export const LAST = SCENES.length - 1;

/** Milliseconds the whole scene takes, camera plus movement plus hold. */
export function durationOf(scene: Scene): number {
  // A scene must not advance while a chip is still fading out.
  const lastMovement = scene.transfers.reduce(
    (latest, transfer) => Math.max(latest, transfer.at + CHIP_LIFE_MS),
    0,
  );
  const revealDone =
    scene.id === "system" ? NODES.length * REVEAL_STAGGER_MS : 0;
  const secondCamera =
    scene.frameThenAt === undefined ? 0 : scene.frameThenAt + CAMERA_MS;

  return (
    CAMERA_MS + Math.max(lastMovement, revealDone, secondCamera) + scene.hold
  );
}

export const TOTAL_MS = SCENES.reduce(
  (total, scene) => total + durationOf(scene),
  0,
);

/* -------------------------------------------------------- derived state */

/** Scene index from which each persistent change is visible. */
const PLAN_FROM = 2;
const CHOSEN_FROM: Record<string, number> = {
  get_payments: 4,
  find_policy: 7,
};
const ROWS_FROM: Record<string, number> = { payments: 5, policies: 7 };
const ANSWER_FROM = 9;
const SUMMARY_FROM = 9;

export const planVisibleAt = (index: number) => index >= PLAN_FROM;

export function planAt(index: number) {
  return PLAN_ITEMS.map((item) => ({
    label: item.label,
    done: index >= item.doneAt,
    /** True on the scene where the tick appears, so it can pop once. */
    justDone: index === item.doneAt,
  }));
}

export const toolChosenAt = (toolId: string, index: number) =>
  CHOSEN_FROM[toolId] !== undefined && index >= CHOSEN_FROM[toolId];

/** A tool the model passed over, once the choice has been made. */
export function toolPassedAt(toolId: string, index: number): boolean {
  const node = NODE_BY_ID[toolId];
  if (!node?.parent) {
    return false;
  }
  const siblingChosen = NODES.some(
    (other) =>
      other.parent === node.parent &&
      other.id !== toolId &&
      toolChosenAt(other.id, index),
  );
  return siblingChosen && !toolChosenAt(toolId, index);
}

export const rowsVisibleAt = (tableId: string, index: number) =>
  ROWS_FROM[tableId] !== undefined && index >= ROWS_FROM[tableId];

export const answerVisibleAt = (index: number) => index >= ANSWER_FROM;
export const summaryVisibleAt = (index: number) => index >= SUMMARY_FROM;
