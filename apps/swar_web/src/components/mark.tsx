"use client";

import { motion, useReducedMotion } from "motion/react";

/**
 * The Swar mark, taken from the dock icon.
 *
 * Eleven parallel strokes lie at -50°, and each one is slid along its own axis
 * by an amount that traces a full sine cycle across the ring. That offset is
 * the whole mark: it is what turns a row of hatching into the zigzag. An
 * earlier version of this file kept the strokes but centred them on a common
 * axis, which drew a tidy level meter and looked nothing like the logo.
 *
 * Coordinates below are the icon's own geometry, measured off the SVG and
 * mapped into a 100-unit box whose ring is centred at (50,50) with r=42.
 * Because the strokes are fine and closely spaced, the mark stops reading
 * below about 30px; the lockup sizes it at 1.3em for that reason rather than
 * matching it to the x-height.
 *
 * Everything is drawn in `currentColor`.
 */

/** x1, y1, x2, y2 for each stroke, ordered across the ring. */
const STROKES: [number, number, number, number][] = [
  [20.31, 40.89, 39.0, 18.61],
  [19.67, 50.59, 39.02, 27.52],
  [20.69, 58.3, 40.14, 35.11],
  [25.1, 61.97, 40.23, 43.93],
  [31.04, 63.82, 45.54, 46.54],
  [39.36, 62.84, 60.83, 37.25],
  [53.95, 54.38, 69.53, 35.81],
  [59.71, 56.45, 74.95, 38.28],
  [60.22, 64.77, 79.39, 41.92],
  [61.35, 72.35, 80.72, 49.27],
  [61.33, 81.3, 79.64, 59.48],
];

/**
 * The stroke direction, -50°. The animation slides each stroke along this
 * vector, so the wave travels the way the mark is already drawn instead of
 * fighting it. Nothing moves perpendicular to the strokes, which is what keeps
 * the spacing even while it runs.
 */
const ALONG = [Math.cos((-50 * Math.PI) / 180), Math.sin((-50 * Math.PI) / 180)];

/** Units each stroke travels either side of rest. The ring has room for 4. */
const TRAVEL = 3.2;

export function SwarMark({
  animated = false,
  className = "",
}: {
  animated?: boolean;
  className?: string;
}) {
  const reduceMotion = useReducedMotion();
  const live = animated && !reduceMotion;

  return (
    <svg
      viewBox="0 0 100 100"
      className={className}
      fill="none"
      stroke="currentColor"
      aria-hidden
      focusable="false"
    >
      <circle cx="50" cy="50" r="42" strokeWidth="1.98" />
      {STROKES.map(([x1, y1, x2, y2], index) => (
        <motion.g
          key={`${x1}-${y1}`}
          animate={
            live
              ? {
                  x: [-TRAVEL * ALONG[0], TRAVEL * ALONG[0], -TRAVEL * ALONG[0]],
                  y: [-TRAVEL * ALONG[1], TRAVEL * ALONG[1], -TRAVEL * ALONG[1]],
                }
              : { x: 0, y: 0 }
          }
          transition={
            live
              ? {
                  duration: 2.6,
                  // The stagger is what makes it a travelling wave rather than
                  // the whole mark sliding back and forth as one piece.
                  delay: index * 0.11,
                  repeat: Infinity,
                  ease: "easeInOut",
                }
              : { duration: 0.3 }
          }
        >
          <line
            x1={x1}
            y1={y1}
            x2={x2}
            y2={y2}
            strokeWidth="3.31"
            strokeLinecap="round"
          />
        </motion.g>
      ))}
    </svg>
  );
}

/**
 * The lockup: the mark stands in for the "s", and "war" is set in the display
 * face beside it. Screen readers get the plain word, since the mark is hidden
 * from them.
 */
export function SwarWordmark({
  animated = false,
  className = "",
  markClassName = "h-[1.3em] w-[1.3em]",
}: {
  animated?: boolean;
  className?: string;
  markClassName?: string;
}) {
  return (
    <span className={`inline-flex items-baseline gap-[0.06em] ${className}`}>
      <SwarMark
        animated={animated}
        className={`${markClassName} translate-y-[0.06em]`}
      />
      <span aria-hidden>war</span>
      <span className="sr-only">swar</span>
    </span>
  );
}
