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
