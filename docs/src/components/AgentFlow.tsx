import React, {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { CANVAS, cameraFor, transformFor, type Rect } from "./AgentFlow/camera";
import NodeView from "./AgentFlow/Nodes";
import Transfers from "./AgentFlow/Transfers";
import Wires from "./AgentFlow/Wires";
import {
  ALWAYS_LIT,
  CAMERA_MS,
  CLOSING,
  FINAL_ANSWER,
  LAST,
  NODES,
  PAYMENT_ROWS,
  PLAN_ITEMS,
  POLICY_ROWS,
  POLICY_RULE,
  PROMPT,
  SCENES,
  SESSION_STATS,
  THINK_MS,
  TRAVEL_MS,
  durationOf,
  rectsFor,
  rowsVisibleAt,
  summaryVisibleAt,
} from "./AgentFlow/story";
import "./AgentFlow.css";

/** Milliseconds between node reveals in the opening scene. */
const REVEAL_STAGGER_MS = 60;

/** Node kinds whose own appearance depends on the scene clock. */
const CLOCKED = new Set(["table", "summary"]);

function useMediaFlag(query: string): boolean {
  const [flag, setFlag] = useState(false);

  useEffect(() => {
    const media = window.matchMedia(query);
    setFlag(media.matches);
    const onChange = (event: MediaQueryListEvent) => setFlag(event.matches);
    media.addEventListener("change", onChange);
    return () => media.removeEventListener("change", onChange);
  }, [query]);

  return flag;
}

export default function AgentFlow() {
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(false);
  /**
   * Milliseconds elapsed inside the current scene. Every effect reads this,
   * so one pause freezes all of them and one resume continues all of them.
   * It starts at the end of scene 0, which is the idle picture.
   */
  const [elapsed, setElapsed] = useState(() => durationOf(SCENES[0]));
  const [announcement, setAnnouncement] = useState("");
  const [viewport, setViewport] = useState({ w: 0, h: 0 });
  const [expanded, setExpanded] = useState(false);

  const reduced = useMediaFlag("(prefers-reduced-motion: reduce)");

  const viewportRef = useRef<HTMLDivElement>(null);
  const expandRef = useRef<HTMLButtonElement>(null);
  const returnFocusTo = useRef<HTMLElement | null>(null);
  const lastFrame = useRef(0);
  const elapsedRef = useRef(durationOf(SCENES[0]));

  const scene = SCENES[index];
  const duration = durationOf(scene);
  const settled = elapsed >= duration;

  /* ------------------------------------------------------------- measure */

  useLayoutEffect(() => {
    const element = viewportRef.current;
    if (!element) {
      return;
    }

    /*
     * The aspect ratio comes from the measured element, not from a breakpoint
     * in this file. The stylesheet owns the ratio, so the camera cannot
     * disagree with it and letterbox the canvas.
     */
    const measure = () =>
      setViewport({ w: element.clientWidth, h: element.clientHeight });
    measure();

    if (typeof ResizeObserver === "undefined") {
      return;
    }
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const aspect = viewport.h > 0 ? viewport.w / viewport.h : 16 / 9;
  const narrow = viewport.w > 0 && viewport.w < 560;

  /* -------------------------------------------------------------- camera */

  /* Scene 9 pulls back out to the whole system once the answer has landed. */
  const secondTarget =
    scene.frameThen !== undefined &&
    scene.frameThenAt !== undefined &&
    elapsed >= CAMERA_MS + scene.frameThenAt;

  const camera: Rect = useMemo(() => {
    const wide = secondTarget ? scene.frameThen! : scene.frame;
    const frame =
      narrow && !secondTarget && scene.frameNarrow ? scene.frameNarrow : wide;
    return cameraFor(
      rectsFor(frame),
      aspect,
      narrow ? 30 : (scene.framePadding ?? 70),
    );
  }, [scene, aspect, secondTarget, narrow]);

  const transform =
    viewport.w > 0 ? transformFor(camera, viewport.w) : undefined;

  /*
   * The establishing shot and the closing pull-out show the whole canvas. On a
   * phone that is about a fifth of full size, where the secondary labels are
   * illegible. Below this scale the canvas drops them and reads as a block
   * diagram; the transcript keeps the detail.
   */
  const far = viewport.w > 0 && viewport.w / camera.w < 0.4;

  /* ---------------------------------------------------------- one clock */

  useEffect(() => {
    if (!playing || reduced) {
      return;
    }

    // Playing from a finished scene replays it rather than skipping it.
    if (elapsedRef.current >= duration) {
      elapsedRef.current = 0;
      setElapsed(0);
    }

    let frame = 0;
    lastFrame.current = performance.now();

    const step = (now: number) => {
      const next = elapsedRef.current + (now - lastFrame.current);
      lastFrame.current = now;

      if (next >= duration) {
        if (index >= LAST) {
          elapsedRef.current = duration;
          setElapsed(duration);
          setPlaying(false);
          return;
        }
        elapsedRef.current = 0;
        setElapsed(0);
        // Autoplay must not talk over the reader.
        setAnnouncement("");
        setIndex((value) => value + 1);
        return;
      }

      elapsedRef.current = next;
      setElapsed(next);
      frame = requestAnimationFrame(step);
    };

    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [playing, reduced, duration, index]);

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
    const element = viewportRef.current;
    if (!element || reduced) {
      return;
    }

    let started = false;
    const observer = new IntersectionObserver(
      (entries) => {
        const entry = entries[0];
        if (!entry) {
          return;
        }
        if (entry.isIntersecting) {
          // Start once, when half of the figure is on screen.
          if (!started) {
            started = true;
            setPlaying(true);
          }
        } else {
          setPlaying(false);
        }
      },
      { threshold: 0.5 },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, [reduced]);

  /* ------------------------------------------------------------ controls */

  const goTo = useCallback((next: number) => {
    const target = Math.min(LAST, Math.max(0, next));
    // A scene reached by hand shows its end state; nothing has to travel.
    elapsedRef.current = durationOf(SCENES[target]);
    setElapsed(elapsedRef.current);
    setPlaying(false);
    setIndex(target);
    setAnnouncement(
      `${target + 1} of ${SCENES.length} · ${SCENES[target].title}`,
    );
  }, []);

  const replay = useCallback(() => {
    elapsedRef.current = 0;
    setElapsed(0);
    setIndex(0);
    setAnnouncement(reduced ? `1 of ${SCENES.length} · ${SCENES[0].title}` : "");
    setPlaying(!reduced);
  }, [reduced]);

  const atEnd = index >= LAST && settled;

  let primaryLabel: string;
  let primaryAction: () => void;

  if (reduced) {
    primaryLabel = index < LAST ? "Next scene" : "Replay";
    primaryAction = index < LAST ? () => goTo(index + 1) : replay;
  } else if (playing) {
    primaryLabel = "Pause";
    primaryAction = () => setPlaying(false);
  } else if (atEnd) {
    primaryLabel = "Replay";
    primaryAction = replay;
  } else {
    primaryLabel = "Play";
    primaryAction = () => setPlaying(true);
  }

  /* -------------------------------------------------------------- expand */

  /*
   * Expanding keeps one instance of the figure and turns it into a fixed
   * overlay. Rendering a second copy into a <dialog> would give two elements
   * the same ref and break the viewport measurement.
   */
  const close = useCallback(() => setExpanded(false), []);

  useEffect(() => {
    if (!expanded) {
      returnFocusTo.current?.focus();
      returnFocusTo.current = null;
      return;
    }

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        close();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    expandRef.current?.focus();
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [expanded, close]);

  const toggleExpanded = () => {
    if (!expanded) {
      returnFocusTo.current = document.activeElement as HTMLElement;
    }
    setExpanded((value) => !value);
  };

  /* -------------------------------------------------------- derived state */

  const motion = Math.max(0, elapsed - CAMERA_MS);

  const lit = useMemo(() => {
    const set = new Set(scene.lit);
    for (const id of ALWAYS_LIT) {
      set.add(id);
    }
    return set;
  }, [scene]);

  /** The model pulses between an outgoing question and the decision returning. */
  const thinking = useMemo(() => {
    const ask = scene.transfers.find((transfer) => transfer.to === "model");
    const back = scene.transfers.find((transfer) => transfer.from === "model");
    if (!ask || !back) {
      return false;
    }
    const from = ask.at + TRAVEL_MS;
    return motion >= from && motion < Math.max(back.at, from + THINK_MS);
  }, [scene, motion]);

  /** Rows arrive once the chip that fetched them lands. */
  const rowsFrom = useMemo(() => {
    const call = scene.transfers.find(
      (transfer) => transfer.to === "payments" || transfer.to === "policies",
    );
    return call ? call.at + TRAVEL_MS : 0;
  }, [scene]);

  const revealCount =
    scene.id === "system"
      ? Math.floor(motion / REVEAL_STAGGER_MS) + 1
      : NODES.length;

  const wiresDrawn =
    scene.id === "system" ? Math.min(1, Math.max(0, (motion - 400) / 500)) : 1;

  /* --------------------------------------------------------------- render */

  return (
    <figure
      className={`af${reduced ? " af-static" : ""}${expanded ? " is-expanded" : ""}`}
    >
      {expanded ? (
        <div className="af-scrim" onClick={close} aria-hidden="true" />
      ) : null}

      <div
        className="af-shell"
        role={expanded ? "dialog" : undefined}
        aria-modal={expanded ? true : undefined}
        aria-label={expanded ? "The multi-agent run, expanded" : undefined}
      >
        <div className="af-viewport" ref={viewportRef}>
          <div
            className={`af-canvas${far ? " is-far" : ""}`}
            style={{ width: CANVAS.w, height: CANVAS.h, transform }}
            aria-hidden="true"
          >
            <Wires lit={lit} drawn={wiresDrawn} />

            {NODES.map((node) => (
              <NodeView
                key={node.id}
                node={node}
                index={index}
                elapsed={
                  CLOCKED.has(node.kind)
                    ? node.kind === "summary" && !summaryVisibleAt(index)
                      ? 0
                      : motion
                    : 0
                }
                lit={lit.has(node.id)}
                revealed={node.reveal < revealCount}
                thinking={node.kind === "model" ? thinking : undefined}
                rowsVisible={rowsVisibleAt(node.id, index)}
                rowsFrom={rowsFrom}
              />
            ))}

            <Transfers
              transfers={scene.transfers}
              motion={motion}
              settled={reduced || settled}
            />
          </div>

          <p
            className={`af-caption${scene.quote ? " is-quote" : ""}`}
            aria-live="off"
          >
            {scene.quote ? `“${scene.caption}”` : scene.caption}
          </p>

          <button
            type="button"
            className="af-expand"
            onClick={toggleExpanded}
            ref={expandRef}
          >
            {expanded ? "Close" : "Expand"}
          </button>
        </div>

        <div className="af-controls">
          <button type="button" className="af-primary" onClick={primaryAction}>
            {primaryLabel}
          </button>
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

          <ol className="af-rail">
            {SCENES.map((entry, position) => (
              <li key={entry.id}>
                <button
                  type="button"
                  className={`af-rail-dot${
                    position === index ? " is-current" : ""
                  }${position < index ? " is-done" : ""}`}
                  onClick={() => goTo(position)}
                  aria-label={`Scene ${position + 1} of ${SCENES.length}: ${entry.title}`}
                  aria-current={position === index ? "step" : undefined}
                >
                  <span className="af-rail-label">{entry.title}</span>
                </button>
              </li>
            ))}
          </ol>
        </div>
      </div>

      <details className="af-transcript">
        <summary>Read the story</summary>

        <p>
          A customer asks: “{PROMPT}” Everything below runs inside an Oracle
          database, except the AI model, which the database calls over HTTPS.
        </p>

        <ol>
          {SCENES.map((entry) => (
            <li key={entry.id}>
              <strong>{entry.title}.</strong>{" "}
              {entry.quote ? `“${entry.caption}”` : entry.caption}
              {entry.transfers.length > 0 ? (
                <span className="af-transcript-note">
                  {" "}
                  (
                  {entry.transfers
                    .map((transfer) => `${transfer.kind}: ${transfer.label}`)
                    .join("; ")}
                  )
                </span>
              ) : null}
            </li>
          ))}
        </ol>

        <p>
          The orchestrator's plan:{" "}
          {PLAN_ITEMS.map((item) => item.label).join(", then ")}.
        </p>
        <p>
          The Billing agent has three of your functions: get_payments,
          get_invoice and issue_refund. The model chose get_payments. The other
          two stayed unused.
        </p>
        <p>
          PAYMENTS rows read:{" "}
          {PAYMENT_ROWS.map(
            (row) =>
              `${row.id}, ${row.amount}, ${row.status}${
                row.match ? " (matches INV-1003)" : ""
              }`,
          ).join("; ")}
          .
        </p>
        <p>
          The Policy agent has find_policy and get_customer_tier. The model
          chose find_policy. REFUND_POLICIES rows read:{" "}
          {POLICY_ROWS.map((row) => `${row.id}, ${row.title}`).join("; ")}. The
          rule that applies: {POLICY_RULE}
        </p>
        <p>Answer: {FINAL_ANSWER}</p>
        <p>
          The run in total:{" "}
          {SESSION_STATS.map((stat) => `${stat.value} ${stat.label}`).join(", ")}
          . {CLOSING}
        </p>
      </details>

      <p className="af-sr" role="status" aria-live="polite">
        {announcement}
      </p>
    </figure>
  );
}
