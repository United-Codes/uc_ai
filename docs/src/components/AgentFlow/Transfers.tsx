/**
 * The travelling chips.
 *
 * A chip rides the same bezier as its wire through `offset-path`, and its
 * position comes from the scene clock rather than a CSS animation. That is
 * what makes Pause exact: the clock stops, so the chip stops where it is.
 *
 * A chip is a messenger, not a label. It fades out shortly after it lands, and
 * the destination's own state carries the information from then on: the tool
 * row lights, the rows appear, the plan ticks, the answer bubble pops. So a
 * scene reached by hand, or read with reduced motion, shows no chips at all --
 * everything a chip said is already on the card.
 */
import React from "react";
import {
  FADE_MS,
  LINGER_MS,
  NODE_BY_ID,
  TRAVEL_MS,
  rectAt,
  type Transfer,
} from "./story";
import { centreOf, headingOf, straightDelta, wirePath } from "./geometry";

/** Canvas units the chip stops short of the card it is heading for. */
const SHORTEN = 18;

interface TransfersProps {
  transfers: Transfer[];
  /** Scene index, so a chip leaves and lands at the height a card is drawn at. */
  index: number;
  /** Milliseconds elapsed since the scene's movement began. */
  motion: number;
  /** True when the scene is showing its end state; no chip is drawn. */
  settled: boolean;
}

/* Ease-out, so a chip leaves quickly and arrives gently. */
const ease = (t: number) => 1 - Math.pow(1 - t, 3);

export default function Transfers({
  transfers,
  index,
  motion,
  settled,
}: TransfersProps) {
  if (settled) {
    return null;
  }

  return (
    <>
      {transfers.map((transfer, position) => {
        const source = NODE_BY_ID[transfer.from];
        const target = NODE_BY_ID[transfer.to];
        if (!source || !target) {
          return null;
        }
        const from = rectAt(source, index);
        const to = rectAt(target, index);

        const since = motion - transfer.at;
        if (since < 0) {
          return null;
        }

        const progress = ease(Math.min(1, since / TRAVEL_MS));
        const past = since - TRAVEL_MS - LINGER_MS;
        const opacity = past <= 0 ? 1 : 1 - past / FADE_MS;
        if (opacity <= 0) {
          return null;
        }

        const origin = centreOf(from);
        const delta = straightDelta(from, to);
        const heading = headingOf(from, to);
        const tone = target.tone === "neutral" ? source.tone : target.tone;

        return (
          <div
            key={`${transfer.from}-${transfer.to}-${position}`}
            className={`af-chip af-chip--${transfer.kind} af-chip--${heading} af-tone-${tone}`}
            style={
              {
                opacity,
                "--af-path": `path("${wirePath(from, to, SHORTEN)}")`,
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
