/**
 * One component per node kind. Every node is positioned in canvas units, so
 * these components never measure anything: the coordinates come from story.ts
 * and the camera scales the whole canvas around them.
 */
import React from "react";
import Icon from "./Icon";
import {
  ANSWER_SOURCES,
  FINAL_ANSWER,
  PROMPT,
  ROWS_BY_TABLE,
  SESSION_STATS,
  answerVisibleAt,
  planAt,
  planNoteAt,
  planVisibleAt,
  summaryVisibleAt,
  toolChosenAt,
  toolPassedAt,
  type StoryNode,
} from "./story";

/** Rows appear one after another, 80ms apart, driven by the scene clock. */
const ROW_STAGGER_MS = 80;

export interface NodeViewProps {
  node: StoryNode;
  index: number;
  /** Milliseconds elapsed inside the current scene. */
  elapsed: number;
  lit: boolean;
  revealed: boolean;
  /** True while the model shows its thinking dots. */
  thinking?: boolean;
  /** A second line for the model card, set by the scene. */
  note?: string;
  rowsVisible?: boolean;
  /** Milliseconds after which the table rows start to appear. */
  rowsFrom?: number;
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

function style(node: StoryNode): React.CSSProperties {
  return { left: node.x, top: node.y, width: node.w, height: node.h };
}

/* --------------------------------------------------------------- boundary */

function Boundary({ node, lit, revealed }: NodeViewProps) {
  return (
    <div className={shellClass(node, lit, revealed)} style={style(node)}>
      <p className="af-boundary-label">
        <span className="af-boundary-db">{node.title}</span>
        <span className="af-boundary-uc">{node.subtitle}</span>
      </p>
    </div>
  );
}

/* ------------------------------------------------------------------- user */

function User({ node, index, lit, revealed }: NodeViewProps) {
  const answer = answerVisibleAt(index);

  return (
    <div className={shellClass(node, lit, revealed)} style={style(node)}>
      <p className="af-node-head">
        <Icon kind="user" />
        <span className="af-node-title">{node.title}</span>
      </p>
      <p className="af-node-sub">{node.subtitle}</p>

      <p className="af-bubble">{PROMPT}</p>

      {answer ? (
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

function Orchestrator({ node, index, lit, revealed }: NodeViewProps) {
  const plan = planAt(index);
  const note = planNoteAt(index);

  return (
    <div className={shellClass(node, lit, revealed)} style={style(node)}>
      <p className="af-node-head">
        <Icon kind="orchestrator" />
        <span className="af-node-title">{node.title}</span>
      </p>
      <p className="af-node-sub">{node.subtitle}</p>

      {planVisibleAt(index) ? (
        <ul className="af-plan">
          {plan.map((item) => (
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

      {note ? <p className="af-plan-note">{note}</p> : null}
    </div>
  );
}

/* ------------------------------------------------------------------ agent */

function Agent({ node, lit, revealed }: NodeViewProps) {
  return (
    <div className={shellClass(node, lit, revealed)} style={style(node)}>
      <p className="af-node-head">
        <Icon kind="agent" />
        <span className="af-node-title">{node.title}</span>
      </p>
      <p className="af-node-sub">{node.subtitle}</p>
    </div>
  );
}

/* ------------------------------------------------------------------- tool */

/*
 * A tool is a row with its name until the model picks it. Then it opens into a
 * code card with the SQL it runs and the argument the model passed, which is
 * what tells a visitor this is a database function and not an API call.
 *
 * The chosen tool is placed last in its agent, so opening it extends into the
 * card's own padding instead of pushing the other rows down.
 */
function Tool({ node, index, lit, revealed }: NodeViewProps) {
  const chosen = toolChosenAt(node.id, index);
  const passed = toolPassedAt(node.id, index);

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
        ...style(node),
        // Collapsed until chosen, so an unused tool stays a single row.
        height: chosen ? node.h : 38,
      }}
    >
      <p className="af-tool-head">
        <span className="af-tool-glyph" aria-hidden="true">
          ƒ
        </span>
        <span className="af-tool-name">{node.title}</span>
        {chosen ? (
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
          {node.bind ? (
            <span className="af-sql-bind">{node.bind}</span>
          ) : null}
        </pre>
      ) : null}
    </div>
  );
}

/* ------------------------------------------------------------------ table */

function Table({
  node,
  index,
  elapsed,
  lit,
  revealed,
  rowsVisible,
  rowsFrom = 0,
}: NodeViewProps) {
  const rows = ROWS_BY_TABLE[node.id] ?? [];
  const columns = node.columns ?? [];

  /* Rows stagger in on the scene they arrive, and are simply there after it. */
  const shown = !rowsVisible
    ? 0
    : elapsed >= rowsFrom
      ? Math.min(
          rows.length,
          Math.floor((elapsed - rowsFrom) / ROW_STAGGER_MS) + 1,
        )
      : 0;
  const settled = rowsVisible && shown >= rows.length;

  return (
    <div className={shellClass(node, lit, revealed)} style={style(node)}>
      <p className="af-node-head">
        <Icon kind="table" size={18} />
        <span className="af-table-kind">table</span>
        <span className="af-table-name">{node.title}</span>
      </p>

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

function Model({ node, lit, revealed, thinking, note }: NodeViewProps) {
  return (
    <div
      className={`${shellClass(node, lit, revealed)}${
        thinking ? " is-thinking" : ""
      }`}
      style={style(node)}
    >
      <p className="af-node-head">
        <Icon kind="model" />
        <span className="af-node-title">{node.title}</span>
        <span className="af-dots" aria-hidden="true">
          <i />
          <i />
          <i />
        </span>
      </p>
      <p className="af-node-sub">{note ?? node.subtitle}</p>
    </div>
  );
}

/* ---------------------------------------------------------------- summary */

function Summary({ node, index, elapsed, lit, revealed }: NodeViewProps) {
  if (!summaryVisibleAt(index)) {
    return null;
  }

  /* Counters run up once, so the numbers register as a total for the run. */
  const progress = Math.min(1, Math.max(0, elapsed / 600));

  return (
    <div className={shellClass(node, lit, revealed)} style={style(node)}>
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
