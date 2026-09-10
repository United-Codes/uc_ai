/**
 * The script of the homepage animation: one refund request handled by an
 * orchestrator and two specialist agents.
 *
 * Story content only. No layout, no timing mechanics, no presentation. Every
 * frame of the animation is derived from a scene index, so Previous, Next, and
 * Replay can restore any scene without carrying state over from the last one.
 *
 * All records and policy text are fictional demo content. Nothing here calls a
 * model and nothing issues a refund.
 */

export type ParticipantId = "user" | "orch" | "billing" | "policy";

export interface Transfer {
  from: ParticipantId;
  to: ParticipantId;
  /** A task travels away from the orchestrator, a result travels back. */
  kind: "task" | "result";
  label: string;
}

export interface Scene {
  id: string;
  /** Short name for the progress label, as in "3 of 8 · Use a tool". */
  title: string;
  /** How long the scene holds before the next one, in milliseconds. */
  ms: number;
  /** The main copy of the scene. */
  caption: string;
  /** Set when the caption is a message, not narration. */
  quote?: boolean;
  transfer?: Transfer;
  /** The active connection when no card travels. */
  link?: [ParticipantId, ParticipantId];
  /** Cards that get the strong accent. */
  focus: ParticipantId[];
}

export const PROMPT =
  "I was charged twice for invoice INV-1003. Can I get a refund?";

export const REQUEST_LABEL = "INV-1003";

export const FINAL_ANSWER =
  "You paid €49 twice for invoice INV-1003. Under the refund policy, the extra €49 qualifies for a refund.";

export const ANSWER_SOURCES = ["Payment records", "Refund policy"];

export const CLOSING =
  "Your agents work together. UC AI connects them to your PL/SQL tools and business data.";

export const WORKSPACE_LABEL = "UC AI · Oracle Database";

export interface PaymentRow {
  id: string;
  invoice: string;
  amount: string;
  status: string;
}

export const PAYMENTS: PaymentRow[] = [
  { id: "PAY-201", invoice: "INV-1003", amount: "€49", status: "Completed" },
  { id: "PAY-202", invoice: "INV-1003", amount: "€49", status: "Completed" },
];

export const POLICY_RULE =
  "Duplicate payment: refund the extra payment to the original payment method.";

export interface Specialist {
  id: ParticipantId;
  name: string;
  job: string;
  /** First scene index where the card exists. */
  appearsAt: number;
  tool: {
    name: string;
    /** First scene index where the tool card is open. */
    opensAt: number;
    /**
     * Scene index from which the tool card keeps only a one-line summary. The
     * finding stays on screen without the full table taking the space.
     */
    collapsesAt?: number;
    summary: string;
  };
}

export const SPECIALISTS: Specialist[] = [
  {
    id: "billing",
    name: "Billing agent",
    job: "Finds the payment facts",
    appearsAt: 1,
    tool: {
      name: "Look up payments",
      opensAt: 2,
      collapsesAt: 4,
      summary: "2 payments · €49 each · completed",
    },
  },
  {
    id: "policy",
    name: "Policy agent",
    job: "Finds the applicable refund rule",
    appearsAt: 1,
    tool: {
      name: "Find refund policy",
      opensAt: 5,
      summary: "Refund the extra payment",
    },
  },
];

/** Findings collect on the request card as the run proceeds. */
export const FINDINGS = [
  { label: "Duplicate payment found", from: 3 },
  { label: "Refund rule found", from: 6 },
];

export const SCENES: Scene[] = [
  {
    id: "request",
    title: "The request",
    ms: 4000,
    caption: PROMPT,
    quote: true,
    focus: ["user", "orch"],
    transfer: {
      from: "user",
      to: "orch",
      kind: "task",
      label: "Refund request · INV-1003",
    },
  },
  {
    id: "choose",
    title: "Choose a specialist",
    ms: 4000,
    caption: "First, ask Billing to look at the payments.",
    focus: ["orch", "billing"],
    link: ["orch", "billing"],
  },
  {
    id: "tool",
    title: "Use a tool",
    ms: 5000,
    caption: "The Billing agent uses a tool to read your payment records.",
    focus: ["billing"],
    transfer: {
      from: "orch",
      to: "billing",
      kind: "task",
      label: "Find payments for INV-1003",
    },
  },
  {
    id: "finding",
    title: "Return the finding",
    ms: 4000,
    caption: "Two completed payments of €49 for the same invoice.",
    focus: ["billing", "orch"],
    transfer: {
      from: "billing",
      to: "orch",
      kind: "result",
      label: "2 completed payments · €49 each",
    },
  },
  {
    id: "next",
    title: "Decide what comes next",
    ms: 4000,
    caption: "A duplicate payment exists. Ask Policy about refunds.",
    focus: ["orch", "policy"],
    transfer: {
      from: "orch",
      to: "policy",
      kind: "task",
      label: "Find the refund rule for a duplicate payment",
    },
  },
  {
    id: "tool-2",
    title: "Use another tool",
    ms: 5000,
    caption:
      "Duplicate payments qualify for a refund of the extra payment.",
    focus: ["policy"],
    link: ["orch", "policy"],
  },
  {
    id: "combine",
    title: "Combine the results",
    ms: 4000,
    caption:
      "The orchestrator combines the payment facts and the refund rule.",
    focus: ["orch"],
    transfer: {
      from: "policy",
      to: "orch",
      kind: "result",
      label: "Refund the extra payment",
    },
  },
  {
    id: "answer",
    title: "Answer the user",
    ms: 5000,
    caption: FINAL_ANSWER,
    quote: true,
    focus: ["orch", "user"],
    transfer: {
      from: "orch",
      to: "user",
      kind: "result",
      label: "Answer ready",
    },
  },
];

export const LAST = SCENES.length - 1;

export function findingsAt(index: number) {
  return FINDINGS.filter((finding) => index >= finding.from);
}

export function toolStateAt(specialist: Specialist, index: number) {
  const { opensAt, collapsesAt } = specialist.tool;
  if (index < opensAt) {
    return "closed" as const;
  }
  if (collapsesAt !== undefined && index >= collapsesAt) {
    return "summary" as const;
  }
  return "open" as const;
}
