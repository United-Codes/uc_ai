import React, {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import {
  ANSWER_SOURCES,
  CLOSING,
  FINAL_ANSWER,
  LAST,
  PAYMENTS,
  POLICY_RULE,
  PROMPT,
  REQUEST_LABEL,
  SCENES,
  SPECIALISTS,
  WORKSPACE_LABEL,
  findingsAt,
  toolStateAt,
  type ParticipantId,
  type Specialist,
} from "./AgentFlow/story";
import "./AgentFlow.css";

/** How long a task or result card takes to travel, in milliseconds. */
const TRAVEL_MS = 520;

function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(query.matches);
    const onChange = (event: MediaQueryListEvent) => setReduced(event.matches);
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, []);

  return reduced;
}

interface Geometry {
  width: number;
  height: number;
  from: { x: number; y: number };
  to: { x: number; y: number };
}

/* ------------------------------------------------------------------ cards */

interface ToolCardProps {
  specialist: Specialist;
  state: "open" | "summary";
}

function ToolCard({ specialist, state }: ToolCardProps) {
  const isPolicy = specialist.id === "policy";

  return (
    <div className={`af-tool af-tool--${state}`}>
      <p className="af-tool-head">
        <span className="af-tool-name">{specialist.tool.name}</span>
        <span className="af-tool-tag">Your PL/SQL function</span>
      </p>

      {state === "summary" ? (
        <p className="af-tool-summary">{specialist.tool.summary}</p>
      ) : isPolicy ? (
        <p className="af-tool-rule">{POLICY_RULE}</p>
      ) : (
        <table className="af-rows">
          <thead>
            <tr>
              <th scope="col">Payment</th>
              <th scope="col">Amount</th>
              <th scope="col">Status</th>
            </tr>
          </thead>
          <tbody>
            {PAYMENTS.map((row) => (
              <tr key={row.id}>
                <td>{row.id}</td>
                <td>{row.amount}</td>
                <td>{row.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

/* -------------------------------------------------------------- component */

export default function AgentFlow() {
  const [started, setStarted] = useState(false);
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [announcement, setAnnouncement] = useState("");
  /** True when the reader stepped here, so the scene shows its end state. */
  const [manual, setManual] = useState(false);
  const [geometry, setGeometry] = useState<Geometry | null>(null);
  const [measureTick, setMeasureTick] = useState(0);

  const reduced = usePrefersReducedMotion();

  const frameRef = useRef<HTMLDivElement>(null);
  const slots = useRef<Partial<Record<ParticipantId, HTMLDivElement | null>>>(
    {},
  );
  /** Milliseconds left in the current scene. Survives a pause. */
  const remaining = useRef(0);
  const resumedAt = useRef(0);

  const scene = started ? SCENES[index] : null;
  const findings = started ? findingsAt(index) : [];
  const showAnswer = started && index >= LAST;
  const setSlot = (id: ParticipantId) => (node: HTMLDivElement | null) => {
    slots.current[id] = node;
  };

  /* ---------------------------------------------------------- one clock */

  useEffect(() => {
    if (!scene || !playing || reduced) {
      return;
    }

    const duration = remaining.current > 0 ? remaining.current : scene.ms;
    remaining.current = duration;
    resumedAt.current = Date.now();

    const timer = window.setTimeout(() => {
      remaining.current = 0;
      if (index >= LAST) {
        setPlaying(false);
        return;
      }
      // Autoplay must not talk over the reader.
      setAnnouncement("");
      setManual(false);
      setIndex((value) => value + 1);
    }, duration);

    return () => {
      window.clearTimeout(timer);
      remaining.current = Math.max(
        0,
        remaining.current - (Date.now() - resumedAt.current),
      );
    };
  }, [scene, playing, reduced, index]);

  /* Playback never resumes on its own after it leaves the reader's view. */
  useEffect(() => {
    const onVisibility = () => {
      if (document.hidden) {
        setPlaying(false);
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, []);

  useEffect(() => {
    const frame = frameRef.current;
    if (!frame) {
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries[0]?.isIntersecting) {
          setPlaying(false);
        }
      },
      { threshold: 0.2 },
    );
    observer.observe(frame);
    return () => observer.disconnect();
  }, []);

  /* ------------------------------------------------------- measurement */

  useLayoutEffect(() => {
    const frame = frameRef.current;
    const pair = scene?.transfer
      ? ([scene.transfer.from, scene.transfer.to] as const)
      : scene?.link;

    if (!frame || !pair) {
      setGeometry(null);
      return;
    }

    const source = slots.current[pair[0]];
    const target = slots.current[pair[1]];
    if (!source || !target) {
      setGeometry(null);
      return;
    }

    const base = frame.getBoundingClientRect();
    const a = source.getBoundingClientRect();
    const b = target.getBoundingClientRect();

    setGeometry({
      width: base.width,
      height: base.height,
      from: {
        x: a.left - base.left + a.width / 2,
        y: a.top - base.top + a.height / 2,
      },
      to: {
        x: b.left - base.left + b.width / 2,
        y: b.top - base.top + b.height / 2,
      },
    });
  }, [scene, started, measureTick]);

  useEffect(() => {
    const frame = frameRef.current;
    if (!frame || typeof ResizeObserver === "undefined") {
      return;
    }
    let last = "";
    const observer = new ResizeObserver(([entry]) => {
      const size = `${Math.round(entry.contentRect.width)}x${Math.round(
        entry.contentRect.height,
      )}`;
      if (size !== last) {
        last = size;
        setMeasureTick((value) => value + 1);
      }
    });
    observer.observe(frame);
    return () => observer.disconnect();
  }, []);

  /* ---------------------------------------------------------- controls */

  const goTo = useCallback((next: number) => {
    remaining.current = 0;
    setPlaying(false);
    setStarted(true);
    setManual(true);
    setIndex(next);
    setAnnouncement(`${next + 1} of ${SCENES.length} · ${SCENES[next].title}`);
  }, []);

  const start = () => {
    remaining.current = 0;
    setManual(reduced);
    setStarted(true);
    setIndex(0);
    setAnnouncement("");
    setPlaying(!reduced);
  };

  const replay = () => {
    remaining.current = 0;
    setManual(reduced);
    setIndex(0);
    setAnnouncement(
      reduced ? `1 of ${SCENES.length} · ${SCENES[0].title}` : "",
    );
    setPlaying(!reduced);
  };

  let primaryLabel: string;
  let primaryAction: () => void;

  if (!started) {
    primaryLabel = "Follow the request";
    primaryAction = start;
  } else if (reduced) {
    primaryLabel = index < LAST ? "Next scene" : "Replay";
    primaryAction = index < LAST ? () => goTo(index + 1) : replay;
  } else if (playing) {
    primaryLabel = "Pause";
    primaryAction = () => setPlaying(false);
  } else if (index >= LAST) {
    primaryLabel = "Replay";
    primaryAction = replay;
  } else {
    primaryLabel = "Play";
    primaryAction = () => setPlaying(true);
  }

  /* ------------------------------------------------------------ render */

  const focus = (id: ParticipantId) =>
    scene?.focus.includes(id) ? " is-focus" : "";

  const transfer = scene?.transfer;
  /* Reduced motion and manual steps both land the card on its destination. */
  const settled = reduced || manual;
  const travel =
    transfer && geometry
      ? {
          left: settled ? geometry.to.x : geometry.from.x,
          top: settled ? geometry.to.y : geometry.from.y,
          dx: settled ? 0 : geometry.to.x - geometry.from.x,
          dy: settled ? 0 : geometry.to.y - geometry.from.y,
        }
      : null;

  return (
    <figure
      className={`af${reduced ? " af-static" : ""}${
        /* Freeze a travel only when playback stopped while it was running. */
        !playing && !settled ? " is-paused" : ""
      }`}
    >
      <div className="af-frame">
        <div className="af-stage" ref={frameRef}>
          <p className="af-run" aria-hidden={!started}>
            <span className="af-run-label">
              {started ? `Request · ${REQUEST_LABEL}` : "Request"}
            </span>
            {findings.map((finding) => (
              <span className="af-finding" key={finding.label}>
                {finding.label}
              </span>
            ))}
          </p>

          <div className="af-columns">
            <section className={`af-convo${focus("user")}`}>
              <p className="af-col-label">You</p>

              <p className="af-bubble">{PROMPT}</p>

              <div className="af-slot" ref={setSlot("user")} />

              {showAnswer ? (
                <div className="af-answer">
                  <p className="af-answer-text">{FINAL_ANSWER}</p>
                  <p className="af-answer-sources">
                    {ANSWER_SOURCES.map((source) => (
                      <span key={source}>{source}</span>
                    ))}
                  </p>
                </div>
              ) : null}
            </section>

            <section className="af-workspace">
              <p className="af-col-label af-col-label--ws">{WORKSPACE_LABEL}</p>

              <div className="af-workspace-grid">
                <div className={`af-card af-card--orch${focus("orch")}`}>
                  <p className="af-card-name">Orchestrator</p>
                  <p className="af-card-job">Coordinates the task</p>
                  <div className="af-slot" ref={setSlot("orch")} />
                </div>

                <div className="af-specialists">
                  {started && index >= SPECIALISTS[0].appearsAt ? null : (
                    <p className="af-hint">
                      The orchestrator picks a specialist for each part of the
                      question. Each specialist uses tools that read your own
                      business records.
                    </p>
                  )}
                  {SPECIALISTS.map((specialist) => {
                    const present = started && index >= specialist.appearsAt;
                    const tool = toolStateAt(specialist, index);

                    return (
                      <div
                        key={specialist.id}
                        className={`af-card af-card--agent${focus(
                          specialist.id,
                        )}${present ? " is-present" : ""}`}
                      >
                        <p className="af-card-name">{specialist.name}</p>
                        <p className="af-card-job">{specialist.job}</p>
                        <div className="af-slot" ref={setSlot(specialist.id)} />
                        {/*
                        Both tool states occupy the same grid cell, so the card
                        reserves the height of the taller one as soon as the
                        specialist appears. The frame then holds one height from
                        scene 2 to the end, and the caption and the controls
                        never move under the reader.
                      */}
                        <div className="af-tool-stack">
                          <div
                            className={`af-tool-layer${
                              tool === "open" ? " is-shown" : ""
                            }`}
                          >
                            <ToolCard specialist={specialist} state="open" />
                          </div>
                          <div
                            className={`af-tool-layer${
                              tool === "summary" ? " is-shown" : ""
                            }`}
                          >
                            <ToolCard specialist={specialist} state="summary" />
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </section>
          </div>

          {geometry ? (
            <svg
              className="af-wire"
              width={geometry.width}
              height={geometry.height}
              viewBox={`0 0 ${geometry.width} ${geometry.height}`}
              aria-hidden="true"
            >
              <line
                x1={geometry.from.x}
                y1={geometry.from.y}
                x2={geometry.to.x}
                y2={geometry.to.y}
              />
            </svg>
          ) : null}

          {transfer && travel ? (
            <div
              // Keyed on the scene only, so a pause does not restart the motion.
              key={index}
              className={`af-travel af-travel--${transfer.kind}${
                settled ? " is-settled" : ""
              }`}
              style={
                {
                  left: `${travel.left}px`,
                  top: `${travel.top}px`,
                  "--af-dx": `${travel.dx}px`,
                  "--af-dy": `${travel.dy}px`,
                  "--af-travel": `${settled ? 0 : TRAVEL_MS}ms`,
                } as React.CSSProperties
              }
              aria-hidden="true"
            >
              <span className="af-travel-inner">{transfer.label}</span>
            </div>
          ) : null}
        </div>
      </div>

      <figcaption className="af-caption">
        {scene ? (
          <p className={`af-caption-text${scene.quote ? " is-quote" : ""}`}>
            {scene.quote ? `“${scene.caption}”` : scene.caption}
          </p>
        ) : (
          <p className="af-caption-text af-caption-text--idle">
            A customer asks one question. Follow it through the agents that
            answer it.
          </p>
        )}
        {showAnswer ? <p className="af-closing">{CLOSING}</p> : null}
      </figcaption>

      <div className="af-controls">
        <button type="button" className="af-primary" onClick={primaryAction}>
          {primaryLabel}
        </button>

        {started ? (
          <>
            <button
              type="button"
              className="af-secondary"
              onClick={() => goTo(index - 1)}
              disabled={index === 0}
            >
              Previous
            </button>
            <button
              type="button"
              className="af-secondary"
              onClick={() => goTo(index + 1)}
              disabled={index >= LAST}
            >
              Next
            </button>
            {primaryLabel === "Replay" ? null : (
              <button type="button" className="af-secondary" onClick={replay}>
                Replay
              </button>
            )}
            <p className="af-progress">
              {index + 1} of {SCENES.length} · {SCENES[index].title}
            </p>
          </>
        ) : null}
      </div>

      <details className="af-transcript">
        <summary>Read the story</summary>
        <ol>
          {SCENES.map((entry) => (
            <li key={entry.id}>
              <strong>{entry.title}.</strong>{" "}
              {entry.quote ? `“${entry.caption}”` : entry.caption}
              {entry.transfer ? (
                <span className="af-transcript-note">
                  {" "}
                  ({entry.transfer.kind === "task" ? "Task" : "Result"}:{" "}
                  {entry.transfer.label})
                </span>
              ) : null}
            </li>
          ))}
        </ol>
        <p>
          Payment records read by the Billing agent:{" "}
          {PAYMENTS.map(
            (row) => `${row.id}, ${row.invoice}, ${row.amount}, ${row.status}`,
          ).join("; ")}
          .
        </p>
        <p>Refund rule read by the Policy agent: {POLICY_RULE}</p>
        <p>
          Answer: {FINAL_ANSWER} Sources: {ANSWER_SOURCES.join(", ")}.
        </p>
      </details>

      <p className="af-sr" role="status" aria-live="polite">
        {announcement}
      </p>
    </figure>
  );
}
