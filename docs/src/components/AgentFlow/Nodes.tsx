/**
 * One component per node kind. Every node is positioned in canvas units, so
 * these components never measure anything: the coordinates come from story.ts
 * and the camera scales the whole canvas around them.
 *
 * Every kind takes the scene clock. Whether a thing is on screen is a question
 * about a moment in the run, never about a scene index alone, so nothing can
 * appear before the chip or the model call that put it there.
 */
import React from "react";
import Icon from "./Icon";
import {
  ANSWER_SOURCES,
  COUNT_MS,
  FINAL_ANSWER,
  PROMPT,
  MOMENTS,
  ROWS_BY_TABLE,
  SESSION_STATS,
  answerVisibleAt,
  laterThan,
  messageFor,
  noteFor,
  planAt,
  planVisibleAt,
  renderRectAt,
  rowsShownAt,
  summaryVisibleAt,
  toolChosenAt,
  toolPassedAt,
  type Landed,
  type Rect,
  type StoryNode,
} from "./story";

export interface NodeViewProps {
  node: StoryNode;
  /** Where the card is drawn right now, from `renderRectAt`. */
  rect: Rect;
  index: number;
  /** Milliseconds since the scene's camera arrived. */
  motion: number;
  lit: boolean;
  revealed: boolean;
  /**
   * True while this card is in a beat: the model card, and the agent card
   * waiting on it. The Policy agent sits too far down the canvas to frame
   * beside the model box without falling to the far view, so an agent shows
   * the dots on its own card and a reader can see it is waiting on something.
   */
  thinking?: boolean;
  /** What the model was given, shown on its card while it thinks. */
  given?: string;
  /** The provider and model this run is using, shown between beats. */
  provider?: string;
  /** Whether the boundary's label is fully inside the camera. */
  labelVisible?: boolean;
}

function shellClass(node: StoryNode, lit: boolean, revealed: boolean) {
  return [
    "af-node",
    `af-node--${node.kind}`,
    `af-tone-${node.tone}`,
    lit ? "is-lit" : "is-dim",
    revealed ? "is-revealed" : "",
  ]
    .filter(Boolean)
    .join(" ");
}

/*
 * Position comes from the story, never from the node's own declared box: an
 * agent card is anchored by its foot and the conversation card grows, so where
 * a card sits is a question about the current moment in the run.
 */
function style(rect: Rect): React.CSSProperties {
  return { left: rect.x, top: rect.y, width: rect.w, height: rect.h };
}

/* --------------------------------------------------------------- boundary */

function Boundary({ node, rect, lit, revealed, labelVisible }: NodeViewProps) {
  /*
   * The label sits at the box's own corner and moves with it. It is dropped
   * when the corner is off camera, so it is never a cropped half word.
   */
  return (
    <div className={shellClass(node, lit, revealed)} style={style(rect)}>
      {labelVisible ? (
        <p className="af-boundary-label">
          <span className="af-boundary-db">{node.title}</span>
          <span className="af-boundary-uc">{node.subtitle}</span>
        </p>
      ) : null}
    </div>
  );
}

/* ------------------------------------------------------------------- user */

function User({ node, rect, index, motion, lit, revealed }: NodeViewProps) {
  return (
    <div className={shellClass(node, lit, revealed)} style={style(rect)}>
      <p className="af-node-head">
        <Icon kind="user" />
        <span className="af-node-title">{node.title}</span>
      </p>

      <p className="af-bubble">{PROMPT}</p>

      {answerVisibleAt(index, motion) ? (
        <div className="af-answer">
          <p className="af-answer-text">{FINAL_ANSWER}</p>
          <p className="af-answer-sources">
            {ANSWER_SOURCES.map((source) => (
              <span key={source}>{source}</span>
            ))}
          </p>
        </div>
      ) : null}
    </div>
  );
}

/* ----------------------------------------------------------- orchestrator */

function Orchestrator({
  node,
  rect,
  index,
  motion,
  lit,
  revealed,
  thinking,
}: NodeViewProps) {
  return (
    <div
      className={`${shellClass(node, lit, revealed)}${
        thinking ? " is-thinking" : ""
      }`}
      style={style(rect)}
    >
      <p className="af-node-head">
        <Icon kind="orchestrator" />
        <span className="af-node-title">{node.title}</span>
        <Dots />
      </p>

      <Message landed={messageFor(node.id, index, motion)} />

      {planVisibleAt(index, motion) ? (
        <ul className="af-plan">
          {planAt(index, motion).map((item) => (
            <li
              key={item.label}
              className={`af-plan-item${item.done ? " is-done" : ""}${
                item.justDone ? " is-new" : ""
              }`}
            >
              <span className="af-plan-box" aria-hidden="true">
                {item.done ? "✓" : ""}
              </span>
              {item.label}
            </li>
          ))}
        </ul>
      ) : null}

      <Note landed={noteFor(node.id, index, motion)} />
    </div>
  );
}

/* ------------------------------------------------------------------ agent */

/*
 * An agent is a titled box until the run is about its turn, when the card
 * opens and its tool rows appear inside it. Its height comes from the scene,
 * so the camera framed the open card before it opened.
 */
function Agent({
  node,
  rect,
  index,
  motion,
  lit,
  revealed,
  thinking,
}: NodeViewProps) {
  const message = messageFor(node.id, index, motion);
  const note = noteFor(node.id, index, motion);

  /*
   * A compact card has one line of room under its title. It shows whichever
   * arrived last: the task it was handed, or what the model told it. The open
   * card has room for both, the task under the title and the note at the foot.
   */
  const compact = rect.h <= (node.compactH ?? 0);
  const noteWins =
    compact && note !== undefined &&
    (message === undefined || laterThan(note.moment, message.moment));

  return (
    <div
      className={`${shellClass(node, lit, revealed)}${
        thinking ? " is-thinking" : ""
      }`}
      style={style(rect)}
    >
      <p className="af-node-head">
        <Icon kind="agent" />
        <span className="af-node-title">{node.title}</span>
        <Dots />
      </p>

      {!compact || !noteWins ? <Message landed={message} /> : null}
      {!compact || noteWins ? <Note landed={note} /> : null}
    </div>
  );
}

/** Shown on a card that is waiting on the model. */
function Dots() {
  return (
    <span className="af-dots" aria-hidden="true">
      <i />
      <i />
      <i />
    </span>
  );
}

/** Where the model's latest answer to this agent stays, once its beat ends. */
function Note({ landed }: { landed: Landed | undefined }) {
  return landed ? (
    <p className="af-note" key={landed.text}>
      {landed.text}
    </p>
  ) : null;
}

/**
 * Where what a token carried is written when it lands. Keyed on the text, so
 * a new message pops in rather than silently replacing the old one.
 */
function Message({ landed }: { landed: Landed | undefined }) {
  return landed ? (
    <span className={`af-msg af-msg--${landed.kind}`} key={landed.text}>
      {landed.text}
    </span>
  ) : null;
}

/* ------------------------------------------------------------------- tool */

/*
 * A tool is a row with its name until the model picks it. Then it opens into a
 * code card with the SQL it runs, with the argument already substituted, which
 * is what tells a visitor this is a database function and not an API call.
 */
function Tool({ node, rect, index, motion, lit, revealed }: NodeViewProps) {
  const chosen = toolChosenAt(node.id, index, motion);
  const passed = toolPassedAt(node.id, index, motion);
  /* The rows coming back land here, in place of the tag. */
  const message = messageFor(node.id, index, motion);

  return (
    <div
      className={[
        shellClass(node, lit, revealed),
        chosen ? "is-chosen" : "",
        passed ? "is-passed" : "",
      ]
        .filter(Boolean)
        .join(" ")}
      style={{
        ...style(rect),
        // Collapsed until chosen, so an unused tool stays a single row.
        height: chosen ? rect.h : 38,
      }}
    >
      <p className="af-tool-head">
        <span className="af-tool-name">{node.title}</span>
        {message ? (
          <Message landed={message} />
        ) : chosen ? (
          <span className="af-tool-tag">PL/SQL function</span>
        ) : null}
      </p>

      {chosen && node.sql ? (
        <pre className="af-sql">
          {node.sql.map((line) => (
            <span className="af-sql-line" key={line}>
              {line}
            </span>
          ))}
        </pre>
      ) : null}
    </div>
  );
}

/* ------------------------------------------------------------------ table */

function Table({ node, rect, index, motion, lit, revealed }: NodeViewProps) {
  const rows = ROWS_BY_TABLE[node.id] ?? [];
  const columns = node.columns ?? [];

  /* Rows stagger in as the query chip lands, and are simply there after it. */
  const shown = rowsShownAt(node.id, index, motion, rows.length);
  const settled = shown >= rows.length;

  return (
    <div className={shellClass(node, lit, revealed)} style={style(rect)}>
      <p className="af-node-head">
        <Icon kind="table" size={22} />
        <span className="af-table-name">{node.title}</span>
      </p>

      <Message landed={messageFor(node.id, index, motion)} />

      <table className="af-rows">
        <thead>
          <tr>
            {columns.map((column) => (
              <th scope="col" key={column}>
                {column}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, position) => (
            <tr
              key={row.cells.join("|")}
              className={[
                position < shown ? "is-in" : "",
                settled && row.match ? "is-match" : "",
              ]
                .filter(Boolean)
                .join(" ")}
            >
              {row.cells.map((cell) => (
                <td key={cell}>{cell}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ------------------------------------------------------------------ model */

/*
 * The model card is where a beat is visible: the dots run and the subtitle
 * says what the model was given. Between beats it says only what it is, which
 * is the point that the provider is interchangeable.
 */
function Model({
  node,
  rect,
  lit,
  revealed,
  thinking,
  given,
  provider,
}: NodeViewProps) {
  return (
    <div
      className={`${shellClass(node, lit, revealed)}${
        thinking ? " is-thinking" : ""
      }`}
      style={style(rect)}
    >
      <p className="af-node-head">
        <Icon kind="model" />
        <span className="af-node-title">{node.title}</span>
        <Dots />
      </p>
      <p className="af-node-sub">{given ? `given ${given}` : provider}</p>
    </div>
  );
}

/* ---------------------------------------------------------------- summary */

function Summary({ node, rect, index, motion, lit, revealed }: NodeViewProps) {
  if (!summaryVisibleAt(index, motion)) {
    return null;
  }

  /*
   * Counters run up once, from the moment the camera finishes pulling back
   * out, so the numbers register as a total for the run.
   */
  const since = motion - MOMENTS.summary.at;
  const progress = Math.min(1, Math.max(0, since / COUNT_MS));

  return (
    <div className={shellClass(node, lit, revealed)} style={style(rect)}>
      {SESSION_STATS.map((stat) => (
        <span className="af-stat" key={stat.label}>
          <b>{Math.round(stat.value * progress)}</b> {stat.label}
        </span>
      ))}
      <span className="af-stat af-stat--note">one uc_ai session</span>
    </div>
  );
}

/* ------------------------------------------------------------------ switch */

const BY_KIND: Record<string, React.FC<NodeViewProps>> = {
  boundary: Boundary,
  user: User,
  orchestrator: Orchestrator,
  agent: Agent,
  tool: Tool,
  table: Table,
  model: Model,
  summary: Summary,
};

function NodeView(props: NodeViewProps) {
  const Component = BY_KIND[props.node.kind];
  return Component ? <Component {...props} /> : null;
}

export default React.memo(NodeView);
