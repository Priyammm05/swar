"use client";

import { motion, useReducedMotion } from "motion/react";

/**
 * The Swar mark: a level meter tilted inside a ring, taken from the dock icon.
 *
 * The dock icon draws that meter with eleven hairline strokes. At wordmark size
 * those strokes land under half a pixel and the mark turns to grey mush, so
 * this keeps the idea and rebuilds it with five heavier bars that still read at
 * fourteen pixels.
 *
 * Everything is drawn in `currentColor`, so the mark inherits whatever the
 * surrounding text is coloured.
 */

const BAR_WIDTH = 7;

/**
 * Centre line and half-height of each bar, in the 100-unit box. The ring's
 * inner edge sits 38 units from the centre; every bar corner is checked to stay
 * inside that, which is what keeps the meter from touching the ring.
 *
 * Four bars rather than five. Five left 6-unit gaps, which close up into a
 * solid blob once the mark is drawn at nav size; these gaps are 11.
 */
const BARS = [
  { x: 23, h: 15 },
  { x: 41, h: 28 },
  { x: 59, h: 25 },
  { x: 77, h: 13 },
];

/** Where each bar sits in its own pulse, so the meter never moves as one block. */
const PULSE = [
  [0.34, 1, 0.52, 0.86],
  [0.62, 0.8, 1, 0.44],
  [1, 0.46, 0.88, 0.62],
  [0.42, 0.94, 0.55, 1],
];

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
      aria-hidden
      focusable="false"
    >
      <circle
        cx="50"
        cy="50"
        r="42"
        stroke="currentColor"
        strokeWidth="8"
      />
      <g transform="rotate(-50 50 50)">
        {BARS.map((bar, index) => (
          <motion.rect
            key={bar.x}
            x={bar.x - BAR_WIDTH / 2}
            y={50 - bar.h}
            width={BAR_WIDTH}
            height={bar.h * 2}
            rx={BAR_WIDTH / 2}
            fill="currentColor"
            style={{ transformBox: "fill-box", transformOrigin: "center" }}
            animate={live ? { scaleY: PULSE[index] } : { scaleY: 1 }}
            transition={
              live
                ? {
                    duration: 1.6 + index * 0.22,
                    repeat: Infinity,
                    repeatType: "mirror",
                    ease: "easeInOut",
                  }
                : { duration: 0.3 }
            }
          />
        ))}
      </g>
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
  markClassName = "h-[0.86em] w-[0.86em]",
}: {
  animated?: boolean;
  className?: string;
  markClassName?: string;
}) {
  return (
    <span className={`inline-flex items-baseline gap-[0.04em] ${className}`}>
      <SwarMark
        animated={animated}
        className={`${markClassName} translate-y-[0.05em]`}
      />
      <span aria-hidden>war</span>
      <span className="sr-only">swar</span>
    </span>
  );
}
