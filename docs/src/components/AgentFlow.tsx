import React, {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { CANVAS, cameraFor, transformFor, type Rect } from "./AgentFlow/camera";
import { ControlIcon, type ControlKind } from "./AgentFlow/Icon";
import NodeView from "./AgentFlow/Nodes";
import Transfers from "./AgentFlow/Transfers";
import Wires from "./AgentFlow/Wires";
import {
  ALWAYS_LIT,
  CAMERA_MS,
  CLOSING,
  FINAL_ANSWER,
  LAST,
  LEVEL0_COUNT,
  MODEL_CALLS,
  NODES,
  NODE_BY_ID,
  PAYMENT_ROWS,
  PROVIDERS,
  PLAN_ITEMS,
  POLICY_ROWS,
  POLICY_RULE,
  PROMPT,
  REVEAL_STAGGER_MS,
  SCENES,
  SESSION_STATS,
  WIRES,
  beatAt,
  durationOf,
  movementEnd,
  otherProvider,
  providerLabel,
  rectAt,
  rectsFor,
  renderRectAt,
  visibleAt,
  wireKey,
} from "./AgentFlow/story";
import "./AgentFlow.css";

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
  /**
   * Which provider the model card names. The first entry is what the server
   * renders; a random one replaces it once, after hydration, so picking it
   * cannot make the server and the client disagree.
   */
  const [provider, setProvider] = useState(0);

  const reduced = useMediaFlag("(prefers-reduced-motion: reduce)");

  useEffect(() => {
    setProvider(Math.floor(Math.random() * PROVIDERS.length));
  }, []);

  const viewportRef = useRef<HTMLDivElement>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);
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

  /*
   * The caption sits below the viewport, not over it, so the camera fits the
   * whole viewport. Measuring the caption made the aspect drift between scenes
   * whenever the text wrapped, which nudged the camera and letterboxed the
   * establishing shot. The stylesheet owns the ratio; nothing here measures it.
   */
  const aspect = viewport.h > 0 ? viewport.w / viewport.h : 16 / 9;
  const narrow = viewport.w > 0 && viewport.w < 560;

  /* -------------------------------------------------------------- camera */

  /* The closing scene pulls back out to the whole system once the answer lands. */
  const secondTarget =
    scene.frameThen !== undefined &&
    scene.frameThenAt !== undefined &&
    elapsed >= CAMERA_MS + scene.frameThenAt;

  const camera: Rect = useMemo(() => {
    const wide = secondTarget ? scene.frameThen! : scene.frame;
    const frame =
      narrow && !secondTarget && scene.frameNarrow ? scene.frameNarrow : wide;
    return cameraFor(
      rectsFor(frame, index),
      aspect,
      narrow ? 40 : (scene.framePadding ?? 110),
      viewport.w,
    );
  }, [scene, index, aspect, secondTarget, narrow, viewport.w]);

  const transform =
    viewport.w > 0 ? transformFor(camera, viewport.w) : undefined;

  /*
   * The establishing shot and the closing pull-out show the whole canvas, which
   * is about half size on a desktop and a fifth of it on a phone. The secondary
   * labels are illegible there, so the canvas drops them and reads as a block
   * diagram. The caption and the transcript keep the detail.
   */
  const far = viewport.w > 0 && viewport.w / camera.w < 0.56;

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

    /*
     * The hold at the end of a scene is for reading what just changed, and
     * nothing reads the clock during it, so publishing `elapsed` there would
     * reconcile the tree at 60fps for no reason. Past the last movement the
     * loop keeps running the clock but stops re-rendering.
     */
    const liveUntil = CAMERA_MS + movementEnd(scene);

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

      const wasLive = elapsedRef.current <= liveUntil;
      elapsedRef.current = next;
      if (wasLive) {
        setElapsed(next);
      }
      frame = requestAnimationFrame(step);
    };

    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [playing, reduced, duration, index, scene]);

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
    // A second viewing names a different provider, which is the whole point.
    setProvider(otherProvider);
    setAnnouncement(reduced ? `1 of ${SCENES.length} · ${SCENES[0].title}` : "");
    setPlaying(!reduced);
  }, [reduced]);

  const atEnd = index >= LAST && settled;

  let primaryLabel: string;
  let primaryIcon: ControlKind;
  let primaryAction: () => void;

  if (reduced) {
    primaryLabel = index < LAST ? "Next scene" : "Replay";
    primaryIcon = index < LAST ? "next" : "replay";
    primaryAction = index < LAST ? () => goTo(index + 1) : replay;
  } else if (playing) {
    primaryLabel = "Pause";
    primaryIcon = "pause";
    primaryAction = () => setPlaying(false);
  } else if (atEnd) {
    primaryLabel = "Replay";
    primaryIcon = "replay";
    primaryAction = replay;
  } else {
    primaryLabel = "Play";
    primaryIcon = "play";
    primaryAction = () => setPlaying(true);
  }

  /* -------------------------------------------------------------- expand */

  /*
   * Expanding uses a real <dialog> in the browser's top layer. Starlight puts
   * `isolation: isolate` on the main pane, so any z-index we pick only counts
   * inside it and the header and the sidebars paint over the overlay. The top
   * layer beats every stacking context.
   *
   * The dialog stays in the DOM and is merely re-opened as modal, so the
   * viewport element and its refs never remount.
   */
  const close = useCallback(() => setExpanded(false), []);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) {
      return;
    }

    if (expanded) {
      if (!dialog.matches(":modal")) {
        dialog.showModal();
      }
      document.documentElement.style.overflow = "hidden";
      expandRef.current?.focus();
      return () => {
        document.documentElement.style.overflow = "";
      };
    }

    if (dialog.open) {
      dialog.close();
    }
    returnFocusTo.current?.focus();
    returnFocusTo.current = null;
  }, [expanded]);

  const toggleExpanded = () => {
    if (!expanded) {
      returnFocusTo.current = document.activeElement as HTMLElement;
    }
    setExpanded((value) => !value);
  };

  /* -------------------------------------------------------- derived state */

  /*
   * Milliseconds since the camera arrived, which is the clock every moment in
   * the story is measured against. A scene shown at its end state passes
   * Infinity, so every "from when" question answers yes and the picture is the
   * exact end of that scene.
   */
  const motion = settled ? Infinity : Math.max(0, elapsed - CAMERA_MS);

  /* The pull-out swaps the answer for the closing statement. */
  const shownCaption =
    secondTarget && scene.captionThen ? scene.captionThen : scene.caption;
  const asQuote = scene.quote && !(secondTarget && scene.captionThen);
  const captionText = asQuote ? `“${shownCaption}”` : shownCaption;

  /* The model call running right now. Nothing travels; the wire runs hot. */
  const beat = useMemo(() => beatAt(index, motion), [index, motion]);
  const hotWire = beat ? wireKey(beat.agent, "model") : null;

  /** The nodes on the canvas at all. Detail exists only where the camera is. */
  const visible = useMemo(() => {
    const set = new Set<string>();
    for (const node of NODES) {
      if (visibleAt(node, index, motion)) {
        set.add(node.id);
      }
    }
    return set;
  }, [index, motion]);

  /*
   * A node is lit only if the camera actually shows it. On a phone a scene
   * frames one card, so without this the scene would highlight nodes that are
   * off screen. The boundary is always lit: it is larger than most cameras.
   */
  const lit = useMemo(() => {
    const set = new Set<string>(ALWAYS_LIT);

    for (const id of scene.lit) {
      const node = NODE_BY_ID[id];
      if (!node || !visible.has(id)) {
        continue;
      }
      const box = rectAt(node, index);
      const onCamera =
        box.x >= camera.x &&
        box.y >= camera.y &&
        box.x + box.w <= camera.x + camera.w &&
        box.y + box.h <= camera.y + camera.h;
      if (onCamera || ALWAYS_LIT.has(id)) {
        set.add(id);
      }
    }

    return set;
  }, [scene, camera, index, visible]);

  /* A wire exists where both of its ends are on the canvas, and lights with them. */
  const wires = useMemo(
    () => WIRES.filter((wire) => visible.has(wire.from) && visible.has(wire.to)),
    [visible],
  );

  const litWires = useMemo(() => {
    const set = new Set<string>();
    for (const wire of wires) {
      if (lit.has(wire.from) && lit.has(wire.to)) {
        set.add(wireKey(wire.from, wire.to));
      }
    }
    return set;
  }, [wires, lit]);

  const boundary = NODE_BY_ID.db;
  const labelRect = {
    x: boundary.x + 20,
    y: boundary.y + 12,
    w: 340,
    h: 40,
  };
  const boundaryLabelVisible =
    labelRect.x >= camera.x &&
    labelRect.y >= camera.y &&
    labelRect.x + labelRect.w <= camera.x + camera.w &&
    labelRect.y + labelRect.h <= camera.y + camera.h;

  /*
   * The opening scene runs off `elapsed`, not `motion`. Every other scene has
   * to wait for the camera to arrive before anything moves, but this one is
   * already where it needs to be, so counting from the camera left the first
   * thing a visitor ever sees as 800ms of an empty dashed box.
   */
  const opening = scene.id === "system" && elapsed < duration;

  const revealCount = opening
    ? Math.floor(elapsed / REVEAL_STAGGER_MS) + 1
    : LEVEL0_COUNT;

  const wiresDrawn = opening
    ? Math.min(1, Math.max(0, (elapsed - 400) / 500))
    : 1;

  /* --------------------------------------------------------------- render */

  return (
    <figure
      className={`af not-content${reduced ? " af-static" : ""}${
        expanded ? " is-expanded" : ""
      }`}
    >
      <dialog
        className="af-dialog"
        ref={dialogRef}
        onClose={close}
        aria-label="The multi-agent run"
      >
        <div className="af-shell">
          <div className="af-frame">
            <div className="af-viewport" ref={viewportRef}>
              <div
                className={`af-canvas${far ? " is-far" : ""}`}
                style={{ width: CANVAS.w, height: CANVAS.h, transform }}
                aria-hidden="true"
              >
                <Wires
                  wires={wires}
                  index={index}
                  lit={litWires}
                  hot={hotWire}
                  drawn={wiresDrawn}
                />

                {NODES.filter((node) => visible.has(node.id)).map((node) => (
                  <NodeView
                    key={node.id}
                    node={node}
                    rect={renderRectAt(node, index, motion, far)}
                    index={index}
                    motion={motion}
                    lit={lit.has(node.id)}
                    revealed={node.reveal < revealCount}
                    thinking={
                      node.kind === "model"
                        ? beat !== undefined
                        : beat?.agent === node.id
                    }
                    given={node.kind === "model" ? beat?.given : undefined}
                    provider={
                      node.kind === "model"
                        ? providerLabel(PROVIDERS[provider])
                        : undefined
                    }
                    labelVisible={
                      node.kind === "boundary" ? boundaryLabelVisible : undefined
                    }
                  />
                ))}

                <Transfers
                  transfers={scene.transfers}
                  index={index}
                  motion={motion}
                  settled={reduced || settled}
                />
              </div>
            </div>

            <p
              className={`af-caption${asQuote ? " is-quote" : ""}`}
              aria-live="off"
            >
              {captionText}
            </p>
          </div>

          <div className="af-controls">
            <button type="button" className="af-primary" onClick={primaryAction}>
              <ControlIcon kind={primaryIcon} />
              {primaryLabel}
            </button>

            <button
              type="button"
              className="af-step"
              onClick={() => goTo(index - 1)}
              disabled={index === 0}
              aria-label="Previous scene"
              title="Previous scene"
            >
              <ControlIcon kind="prev" />
            </button>
            <button
              type="button"
              className="af-step"
              onClick={() => goTo(index + 1)}
              disabled={index >= LAST}
              aria-label="Next scene"
              title="Next scene"
            >
              <ControlIcon kind="next" />
            </button>

            <ol className="af-rail">
              {SCENES.map((entry, position) => (
                <li key={entry.id}>
                  <button
                    type="button"
                    className={`af-dot${position === index ? " is-current" : ""}${
                      position < index ? " is-done" : ""
                    }`}
                    onClick={() => goTo(position)}
                    aria-label={`Scene ${position + 1} of ${SCENES.length}: ${entry.title}`}
                    aria-current={position === index ? "step" : undefined}
                    title={entry.title}
                  />
                </li>
              ))}
            </ol>

            <p className="af-progress">
              <span className="af-progress-count">
                {index + 1} / {SCENES.length}
              </span>
              <span className="af-progress-title"> · {scene.title}</span>
            </p>

            <button
              type="button"
              className="af-expand"
              onClick={toggleExpanded}
              ref={expandRef}
              aria-label={expanded ? "Close the expanded view" : "Expand"}
              title={expanded ? "Close" : "Expand"}
            >
              <ControlIcon kind={expanded ? "close" : "expand"} />
              <span className="af-expand-label">
                {expanded ? "Close" : "Expand"}
              </span>
            </button>
          </div>
        </div>
      </dialog>

      <details className="af-transcript">
        <summary>Read the story</summary>

        <p>
          A customer asks: “{PROMPT}” Everything below runs inside an Oracle
          database, except the AI model, which the database calls over HTTPS.
          This run uses {providerLabel(PROVIDERS[provider])}. UC AI takes any of{" "}
          {PROVIDERS.map((entry) => entry.name).join(", ")}.
        </p>

        <ol>
          {SCENES.map((entry) => (
            <li key={entry.id}>
              <strong>{entry.title}.</strong>{" "}
              {entry.quote ? `“${entry.caption}”` : entry.caption}
              {entry.beats.length > 0 || entry.transfers.length > 0 ? (
                <span className="af-transcript-note">
                  {" "}
                  (
                  {[
                    ...entry.beats.map(
                      (item) =>
                        `model call: ${item.agent} sends ${item.given}` +
                        (item.yields ? `, and gets back “${item.yields}”` : ""),
                    ),
                    ...entry.transfers.map(
                      (item) => `${item.kind}: ${item.label}`,
                    ),
                  ].join("; ")}
                  )
                </span>
              ) : null}
            </li>
          ))}
        </ol>

        <p>
          The run makes {MODEL_CALLS} model calls in all. Every agent is its own
          loop: it asks the model what to do, runs what the model picked, and
          asks again with the result.
        </p>
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
          get_payments runs: select amount from payments where invoice_id =
          'INV-1003'. The PAYMENTS rows it reads:{" "}
          {PAYMENT_ROWS.map(
            (row) => `${row.cells.join(", ")}${row.match ? " (selected)" : ""}`,
          ).join("; ")}
          .
        </p>
        <p>
          The Policy agent has find_policy and get_customer_tier. The model
          chose find_policy, which runs: select rule_text from refund_policies
          where reason_code = 'duplicate_payment'. The REFUND_POLICIES rows it
          reads:{" "}
          {POLICY_ROWS.map(
            (row) => `${row.cells.join(", ")}${row.match ? " (selected)" : ""}`,
          ).join("; ")}
          . The rule that applies: {POLICY_RULE}
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
