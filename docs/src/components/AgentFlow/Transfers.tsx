/**
 * The travelling tokens.
 *
 * A token rides the same bezier as its wire through `offset-path`, and its
 * position comes from the scene clock rather than a CSS animation. That is
 * what makes Pause exact: the clock stops, so the token stops where it is.
 *
 * A token carries no text. The gaps between cards are 40 to 60 canvas units
 * and a label is 150 to 250, so a label in flight always sat on a card's own
 * text, and when it landed it covered the thing it was about. The token is a
 * 28-unit dot; what it hands over is written into the destination card's
 * message line the moment it lands (`messageFor` in story.ts), and stays there
 * as state. So a scene reached by hand, or read with reduced motion, shows no
 * tokens at all -- everything a token carried is already on the card.
 */
import React from "react";
import {
  FADE_MS,
  NODE_BY_ID,
  TRAVEL_MS,
  rectAt,
  type Transfer,
} from "./story";
import { centreOf, straightDelta, wirePath } from "./geometry";

/** Diameter of a token, in canvas units. Matches `.af-chip-inner`. */
export const TOKEN = 28;

/** The path stops short so the token touches the card's border, not its text. */
const SHORTEN = TOKEN / 2 + 2;

interface TransfersProps {
  transfers: Transfer[];
  /** Scene index, so a token leaves and lands at the height a card is drawn at. */
  index: number;
  /** Milliseconds elapsed since the scene's movement began. */
  motion: number;
  /** True when the scene is showing its end state; no token is drawn. */
  settled: boolean;
}

/* Ease-out, so a token leaves quickly and arrives gently. */
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
        /* The token is gone as soon as its message is on the card. */
        const past = since - TRAVEL_MS;
        const opacity = past <= 0 ? 1 : 1 - past / FADE_MS;
        if (opacity <= 0) {
          return null;
        }

        const origin = centreOf(from);
        const delta = straightDelta(from, to);
        const tone = target.tone === "neutral" ? source.tone : target.tone;

        return (
          <div
            key={`${transfer.from}-${transfer.to}-${position}`}
            className={`af-chip af-chip--${transfer.kind} af-tone-${tone}`}
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
            aria-hidden="true"
          >
            <span className="af-chip-inner" />
          </div>
        );
      })}
    </>
  );
}
