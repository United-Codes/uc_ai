/**
 * The wires, as one SVG in canvas coordinates. It sits under the nodes, so a
 * wire only shows in the space between the cards it joins.
 *
 * The parent decides which wires exist and which are lit, because both depend
 * on the scene: a wire to a table exists only while the camera is on its
 * agent, and the wire to the model runs hot for the length of a beat. A hot
 * wire is what a model call looks like when nothing travels.
 */
import React from "react";
import { CANVAS } from "./camera";
import { NODE_BY_ID, type Wire, rectAt, wireKey } from "./story";
import { wirePath } from "./geometry";

interface WiresProps {
  /** The wires on the canvas in this scene. */
  wires: Wire[];
  /** Scene index, so a wire meets a card at the height that card is drawn at. */
  index: number;
  /** Keys of the wires drawn at full strength. */
  lit: Set<string>;
  /** Key of the wire carrying the model call happening right now. */
  hot: string | null;
  /**
   * The opening scene draws the wires on. A value below 1 leaves the tail of
   * every wire hidden through `stroke-dashoffset`.
   */
  drawn: number;
}

export default function Wires({ wires, index, lit, hot, drawn }: WiresProps) {
  return (
    <svg
      className="af-wires"
      viewBox={`0 0 ${CANVAS.w} ${CANVAS.h}`}
      width={CANVAS.w}
      height={CANVAS.h}
      aria-hidden="true"
    >
      {wires.map((wire) => {
        const from = NODE_BY_ID[wire.from];
        const to = NODE_BY_ID[wire.to];
        if (!from || !to) {
          return null;
        }

        const key = wireKey(wire.from, wire.to);

        return (
          <path
            key={key}
            className={`af-wire${lit.has(key) ? " is-lit" : ""}${
              key === hot ? " is-hot" : ""
            }`}
            d={wirePath(rectAt(from, index), rectAt(to, index))}
            // A normalised length lets one dashoffset value drive every wire.
            pathLength={1}
            strokeDasharray={1}
            strokeDashoffset={1 - drawn}
          />
        );
      })}
    </svg>
  );
}
