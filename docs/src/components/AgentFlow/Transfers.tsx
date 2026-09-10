/**
 * The travelling chips.
 *
 * A chip rides the same bezier as its wire through `offset-path`, and its
 * position comes from the scene clock rather than a CSS animation. That is
 * what makes Pause exact: the clock stops, so the chip stops where it is.
 */
import React from "react";
import { NODE_BY_ID, TRAVEL_MS, type Transfer } from "./story";
import { centreOf, straightDelta, wirePath } from "./geometry";

interface TransfersProps {
  transfers: Transfer[];
  /** Milliseconds elapsed since the scene's movement began. */
  motion: number;
  /** True when every chip should sit at its destination with no travel. */
  settled: boolean;
}

/* Ease-out, so a chip leaves quickly and arrives gently. */
const ease = (t: number) => 1 - Math.pow(1 - t, 3);

export default function Transfers({
  transfers,
  motion,
  settled,
}: TransfersProps) {
  return (
    <>
      {transfers.map((transfer, position) => {
        const from = NODE_BY_ID[transfer.from];
        const to = NODE_BY_ID[transfer.to];
        if (!from || !to) {
          return null;
        }

        const raw = settled ? 1 : (motion - transfer.at) / TRAVEL_MS;
        if (raw < 0) {
          return null;
        }

        const progress = ease(Math.min(1, raw));
        const origin = centreOf(from);
        const delta = straightDelta(from, to);

        return (
          <div
            key={`${transfer.from}-${transfer.to}-${position}`}
            className={`af-chip af-chip--${transfer.kind} af-tone-${to.tone === "neutral" ? from.tone : to.tone}`}
            style={
              {
                "--af-path": `path("${wirePath(from, to)}")`,
                "--af-progress": `${progress * 100}%`,
                "--af-origin-x": `${origin.x}px`,
                "--af-origin-y": `${origin.y}px`,
                "--af-dx": `${delta.dx * progress}px`,
                "--af-dy": `${delta.dy * progress}px`,
              } as React.CSSProperties
            }
          >
            <span className="af-chip-inner">{transfer.label}</span>
          </div>
        );
      })}
    </>
  );
}
