/**
 * Wire geometry in canvas units.
 *
 * Curved cubic beziers between node edges. A straight dashed line reads like
 * a diagram tool export, so every wire bends.
 *
 * Pure functions. The tokens reuse the same paths through `offset-path`, so a
 * token always travels the wire the reader can see.
 */

import type { Rect } from "./camera";

interface Point {
  x: number;
  y: number;
}

const centre = (r: Rect): Point => ({ x: r.x + r.w / 2, y: r.y + r.h / 2 });

/**
 * The path from `a` to `b`, leaving and entering on whichever sides face each
 * other. Control points are offset along the axis of travel.
 *
 * `shorten` stops the path that many canvas units before the destination edge.
 * A token rides this path, so ending short is what lets it touch the card's
 * border rather than sit on it.
 */
export function wirePath(a: Rect, b: Rect, shorten = 0): string {
  const ca = centre(a);
  const cb = centre(b);

  // Side by side: leave the right edge, enter the left edge.
  if (b.x >= a.x + a.w) {
    const x1 = a.x + a.w;
    const x2 = Math.max(x1, b.x - shorten);
    const bend = Math.max(50, (x2 - x1) * 0.55);
    return `M ${x1} ${ca.y} C ${x1 + bend} ${ca.y}, ${x2 - bend} ${cb.y}, ${x2} ${cb.y}`;
  }

  if (a.x >= b.x + b.w) {
    const x1 = a.x;
    const x2 = Math.min(x1, b.x + b.w + shorten);
    const bend = Math.max(50, (x1 - x2) * 0.55);
    return `M ${x1} ${ca.y} C ${x1 - bend} ${ca.y}, ${x2 + bend} ${cb.y}, ${x2} ${cb.y}`;
  }

  // Stacked: leave the top or bottom edge.
  if (b.y + b.h <= a.y) {
    const y1 = a.y;
    const y2 = Math.min(y1, b.y + b.h + shorten);
    const bend = Math.max(50, (y1 - y2) * 0.55);
    return `M ${ca.x} ${y1} C ${ca.x} ${y1 - bend}, ${cb.x} ${y2 + bend}, ${cb.x} ${y2}`;
  }

  const y1 = a.y + a.h;
  const y2 = Math.max(y1, b.y - shorten);
  const bend = Math.max(50, (y2 - y1) * 0.55);
  return `M ${ca.x} ${y1} C ${ca.x} ${y1 + bend}, ${cb.x} ${y2 - bend}, ${cb.x} ${y2}`;
}

/** Straight fall back for browsers without `offset-path`. */
export function straightDelta(a: Rect, b: Rect): { dx: number; dy: number } {
  const ca = centre(a);
  const cb = centre(b);
  return { dx: cb.x - ca.x, dy: cb.y - ca.y };
}

export const centreOf = centre;
