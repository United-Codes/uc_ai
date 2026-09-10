/**
 * Camera math for the AgentFlow canvas.
 *
 * The canvas is one fixed logical surface. A scene names the nodes it is
 * about, and these functions turn that list into the rectangle the viewport
 * shows. Scenes never hold coordinates, so the layout can move without
 * retuning every scene.
 *
 * Pure functions only. No DOM, no React.
 */

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** Logical size of the canvas, in canvas units. */
export const CANVAS: Rect = { x: 0, y: 0, w: 1600, h: 900 };

/** The smallest rectangle that contains all of `rects`. */
export function boundsOf(rects: Rect[]): Rect {
  if (rects.length === 0) {
    return CANVAS;
  }

  let left = Infinity;
  let top = Infinity;
  let right = -Infinity;
  let bottom = -Infinity;

  for (const rect of rects) {
    left = Math.min(left, rect.x);
    top = Math.min(top, rect.y);
    right = Math.max(right, rect.x + rect.w);
    bottom = Math.max(bottom, rect.y + rect.h);
  }

  return { x: left, y: top, w: right - left, h: bottom - top };
}

export function padRect(rect: Rect, pad: number): Rect {
  return {
    x: rect.x - pad,
    y: rect.y - pad,
    w: rect.w + pad * 2,
    h: rect.h + pad * 2,
  };
}

/** Grows the shorter side so the rectangle matches `aspect`, keeping its centre. */
export function fitAspect(rect: Rect, aspect: number): Rect {
  const current = rect.w / rect.h;

  if (Math.abs(current - aspect) < 0.0001) {
    return rect;
  }

  if (current < aspect) {
    const width = rect.h * aspect;
    return {
      x: rect.x - (width - rect.w) / 2,
      y: rect.y,
      w: width,
      h: rect.h,
    };
  }

  const height = rect.w / aspect;
  return {
    x: rect.x,
    y: rect.y - (height - rect.h) / 2,
    w: rect.w,
    h: height,
  };
}

/**
 * Slides the rectangle back inside the canvas so a zoomed scene never shows
 * empty space beside the canvas. A rectangle wider or taller than the canvas
 * stays centred on it instead.
 */
export function clampToCanvas(rect: Rect): Rect {
  const result = { ...rect };

  if (result.w >= CANVAS.w) {
    result.x = CANVAS.x - (result.w - CANVAS.w) / 2;
  } else {
    result.x = Math.min(
      Math.max(result.x, CANVAS.x),
      CANVAS.x + CANVAS.w - result.w,
    );
  }

  if (result.h >= CANVAS.h) {
    result.y = CANVAS.y - (result.h - CANVAS.h) / 2;
  } else {
    result.y = Math.min(
      Math.max(result.y, CANVAS.y),
      CANVAS.y + CANVAS.h - result.h,
    );
  }

  return result;
}

/**
 * Largest scale the camera will use. Without a cap, a two-node scene in the
 * 1400px expanded view reaches 1.7 and the labels become comically large.
 * Expanding should show more context, not bigger letters.
 */
export const MAX_SCALE = 1.15;

/**
 * The camera rectangle for a set of nodes.
 *
 * @param rects          the nodes to frame; an empty list frames the whole canvas
 * @param aspect         the viewport aspect ratio, as width / height
 * @param pad            padding around the nodes, in canvas units
 * @param viewportWidth  used to hold the scale at or below MAX_SCALE
 */
export function cameraFor(
  rects: Rect[],
  aspect: number,
  pad = 70,
  viewportWidth = 0,
): Rect {
  if (rects.length === 0) {
    return fitAspect(CANVAS, aspect);
  }

  let rect = fitAspect(padRect(boundsOf(rects), pad), aspect);

  const minWidth = viewportWidth / MAX_SCALE;
  if (viewportWidth > 0 && rect.w < minWidth) {
    rect = fitAspect(
      {
        x: rect.x - (minWidth - rect.w) / 2,
        y: rect.y,
        w: minWidth,
        h: rect.h,
      },
      aspect,
    );
  }

  return clampToCanvas(rect);
}

/** The canvas transform that puts `camera` in a viewport of `viewportWidth`. */
export function transformFor(camera: Rect, viewportWidth: number): string {
  const scale = viewportWidth / camera.w;
  const tx = -camera.x * scale;
  const ty = -camera.y * scale;
  return `translate(${tx}px, ${ty}px) scale(${scale})`;
}
