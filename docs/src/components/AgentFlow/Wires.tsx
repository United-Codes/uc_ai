/**
 * The wires, as one SVG in canvas coordinates. It sits under the nodes, so a
 * wire only shows in the space between the cards it joins.
 */
import React from "react";
import { CANVAS } from "./camera";
import { NODE_BY_ID, WIRES } from "./story";
import { wirePath } from "./geometry";

interface WiresProps {
  /** Nodes drawn at full strength. A wire is lit when both ends are. */
  lit: Set<string>;
  /**
   * Scene 0 draws the wires on. A value below 1 leaves the tail of every
   * wire hidden through `stroke-dashoffset`.
   */
  drawn: number;
}

export default function Wires({ lit, drawn }: WiresProps) {
  return (
    <svg
      className="af-wires"
      viewBox={`0 0 ${CANVAS.w} ${CANVAS.h}`}
      width={CANVAS.w}
      height={CANVAS.h}
      aria-hidden="true"
    >
      {WIRES.map((wire) => {
        const from = NODE_BY_ID[wire.from];
        const to = NODE_BY_ID[wire.to];
        if (!from || !to) {
          return null;
        }

        const isLit = lit.has(wire.from) && lit.has(wire.to);

        return (
          <path
            key={`${wire.from}-${wire.to}`}
            className={`af-wire${isLit ? " is-lit" : ""}`}
            d={wirePath(from, to)}
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
