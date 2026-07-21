"use client";

import { motion, useReducedMotion } from "motion/react";

/**
 * The hero mark tells the whole product in one shape: rambling speech travels
 * down a curve, passes through the bar, and leaves as clean text on a ribbon.
 *
 * The curve deliberately sits *below* the headline rather than behind it. Run
 * through the centred column it collided with the type and read as a rendering
 * fault instead of a deliberate mark.
 */

// Sized to land on the bar at the end of the curve. Longer and it overshoots
// the path and continues off the right edge as a straight line.
const MESSY =
  "um so I was thinking maybe we could push the release to Friday";

const CLEAN =
  "Let's push the release to Friday. The migration is only half done and nobody has reviewed it yet.";

export function Hero() {
  const reduceMotion = useReducedMotion();

  return (
    <section className="relative isolate overflow-hidden px-5 pb-16 pt-28 sm:px-8 sm:pt-36">
      <div className="mx-auto max-w-4xl text-center">
        <motion.p
          initial={reduceMotion ? false : { opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="mb-7 inline-flex items-center gap-2 rounded-full border border-rule bg-paper/70 px-3.5 py-1.5 font-mono text-[11px] uppercase tracking-widest text-ink-soft"
        >
          <span className="h-1.5 w-1.5 rounded-full bg-acid-deep" />
          runs offline on your machine
        </motion.p>

        <motion.h1
          initial={reduceMotion ? false : { opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, ease: [0.2, 0.8, 0.2, 1] }}
          className="display-wonk font-display text-[clamp(2.75rem,9vw,6.5rem)] font-normal leading-[0.92] text-ink"
        >
          Talk to your machine.
          <br />
          <span className="text-ink-faint">Nothing leaves it.</span>
        </motion.h1>

        <motion.p
          initial={reduceMotion ? false : { opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.1 }}
          className="mx-auto mt-7 max-w-xl text-pretty text-base leading-relaxed text-ink-soft sm:text-lg"
        >
          Hold a key, say the thing, and the words land where your cursor is.
          The audio is transcribed on your own machine. No upload, no account,
          no internet.
        </motion.p>

        <motion.div
          initial={reduceMotion ? false : { opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.18 }}
          className="mt-10 flex flex-col items-center gap-4"
        >
          <a
            href="#demo"
            className="group inline-flex items-center gap-3 rounded-full bg-ink px-8 py-4 text-base font-medium text-paper transition-transform duration-200 hover:scale-[1.03] active:scale-[0.98]"
          >
            See it work
            <span className="transition-transform duration-200 group-hover:translate-y-0.5">
              ↓
            </span>
          </a>
          <p className="font-mono text-[11px] uppercase tracking-widest text-ink-faint">
            macOS · English · always free
          </p>
        </motion.div>
      </div>

      <SpeechToText reduceMotion={!!reduceMotion} clean={CLEAN} messy={MESSY} />
    </section>
  );
}

/**
 * Rambling speech on a descending curve, the bar at the bottom of it, and the
 * cleaned sentence scrolling away on a ribbon.
 */
function SpeechToText({
  reduceMotion,
  clean,
  messy,
}: {
  reduceMotion: boolean;
  clean: string;
  messy: string;
}) {
  return (
    <div className="relative mt-16 sm:mt-20" aria-hidden>
      {/* The curve. Hidden on phones, where there is not enough width for an
          arc to read as anything but a broken line of text. */}
      <div className="pointer-events-none hidden h-[150px] w-full sm:block sm:h-[190px]">
        <svg
          viewBox="0 0 1200 190"
          className="h-full w-full"
          preserveAspectRatio="none"
        >
          <defs>
            <path
              id="swar-speech-curve"
              d="M 40 22 C 300 6, 430 130, 600 172"
              fill="none"
            />
          </defs>
          <motion.text
            className="fill-ink-faint"
            style={{ fontSize: 17 }}
            initial={reduceMotion ? false : { opacity: 0 }}
            animate={{ opacity: 0.62 }}
            transition={{ duration: 1, delay: 0.4 }}
          >
            <textPath href="#swar-speech-curve" startOffset="1%">
              {messy}
            </textPath>
          </motion.text>
        </svg>
      </div>

      {/* The bar the speech passes through. */}
      <motion.div
        initial={reduceMotion ? false : { opacity: 0, scale: 0.9 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.5, delay: 0.7, ease: [0.2, 0.8, 0.2, 1] }}
        className="relative z-10 mx-auto flex w-fit items-center gap-3 rounded-full border border-ink/10 bg-ink px-5 py-3 shadow-[0_18px_40px_-20px_rgba(20,20,15,0.55)]"
      >
        <div className="flex h-5 items-center gap-[3px]">
          {Array.from({ length: 22 }).map((_, index) => {
            const seed = Math.abs(Math.sin(index * 12.9898) * 43758.5453) % 1;
            const height = 4 + seed * 14;
            return (
              <motion.span
                key={index}
                className="w-[2px] rounded-full bg-paper"
                animate={
                  reduceMotion
                    ? { height }
                    : { height: [height * 0.3, height, height * 0.55] }
                }
                transition={
                  reduceMotion
                    ? { duration: 0 }
                    : {
                        duration: 0.7 + seed * 0.5,
                        repeat: Infinity,
                        repeatType: "mirror",
                        ease: "easeInOut",
                      }
                }
              />
            );
          })}
        </div>
        <span className="font-mono text-[11px] uppercase tracking-widest text-paper/55">
          EN
        </span>
      </motion.div>

      {/* Clean text leaving. */}
      <div className="relative -mt-6 -rotate-[1.2deg] select-none overflow-hidden">
        <div className="swar-marquee flex w-max bg-ink py-3 sm:py-4">
          {[0, 1].map((copy) => (
            <div key={copy} className="flex shrink-0">
              {Array.from({ length: 3 }).map((_, index) => (
                <span
                  key={index}
                  className="whitespace-nowrap px-6 text-base font-medium text-paper sm:text-xl"
                >
                  {clean}
                  <span className="px-6 text-acid">✦</span>
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
