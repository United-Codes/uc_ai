/**
 * One inline glyph per node kind. Hand written so the island needs no icon
 * package; Starlight's own Icon component is Astro-only and is not available
 * inside a React island.
 */
import React from "react";
import type { NodeKind } from "./story";

const PATHS: Partial<Record<NodeKind, React.ReactNode>> = {
  user: (
    <>
      <circle cx="12" cy="8" r="3.5" />
      <path d="M5 20a7 7 0 0 1 14 0" />
    </>
  ),
  orchestrator: (
    <>
      <path d="M5 12h5" />
      <path d="M14 6h5M14 18h5" />
      <path d="M10 12c0-3.3 1.3-6 4-6M10 12c0 3.3 1.3 6 4 6" />
      <circle cx="4" cy="12" r="1.6" />
      <circle cx="20" cy="6" r="1.6" />
      <circle cx="20" cy="18" r="1.6" />
    </>
  ),
  agent: (
    <>
      <rect x="4" y="7" width="16" height="12" rx="3" />
      <path d="M12 3v4" />
      <circle cx="9.5" cy="13" r="1.1" />
      <circle cx="14.5" cy="13" r="1.1" />
    </>
  ),
  tool: (
    <>
      <path d="M14.5 3.5a4.5 4.5 0 0 0-5.6 5.6L3.6 14.4a1.5 1.5 0 0 0 0 2.1l1.9 1.9a1.5 1.5 0 0 0 2.1 0l5.3-5.3a4.5 4.5 0 0 0 5.6-5.6l-2.7 2.7-2.5-2.5Z" />
    </>
  ),
  table: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="M3 10h18M9 10v9M15 10v9" />
    </>
  ),
  model: (
    <>
      <path d="M7 18a4 4 0 0 1-.4-8A5.5 5.5 0 0 1 17.3 9 3.5 3.5 0 0 1 17 18Z" />
    </>
  ),
};

interface IconProps {
  kind: NodeKind;
  size?: number;
}

export default function Icon({ kind, size = 22 }: IconProps) {
  const path = PATHS[kind];
  if (!path) {
    return null;
  }

  return (
    <svg
      className="af-icon"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {path}
    </svg>
  );
}

/** Glyphs for the playback controls. */
const CONTROL_PATHS = {
  play: <path d="M8 5.5v13l11-6.5-11-6.5Z" fill="currentColor" stroke="none" />,
  pause: (
    <>
      <path d="M9 5v14" strokeWidth="2.6" />
      <path d="M15 5v14" strokeWidth="2.6" />
    </>
  ),
  replay: (
    <>
      <path d="M20 12a8 8 0 1 1-2.6-5.9" />
      <path d="M20 4v4h-4" />
    </>
  ),
  prev: <path d="M14.5 6 9 12l5.5 6" />,
  next: <path d="M9.5 6 15 12l-5.5 6" />,
  expand: <path d="M9 4H4v5M15 4h5v5M15 20h5v-5M9 20H4v-5" />,
  close: <path d="M6 6l12 12M18 6 6 18" />,
} as const;

export type ControlKind = keyof typeof CONTROL_PATHS;

export function ControlIcon({
  kind,
  size = 16,
}: {
  kind: ControlKind;
  size?: number;
}) {
  return (
    <svg
      className="af-ctrl-icon"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {CONTROL_PATHS[kind]}
    </svg>
  );
}
