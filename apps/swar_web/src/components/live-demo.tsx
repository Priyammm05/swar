"use client";

import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useCallback, useEffect, useRef, useState } from "react";

/**
 * The bar that sits above every app on the desktop, reproduced on the web.
 *
 * It plays the thing that actually distinguishes Swar: segments settle *while*
 * you are still speaking, so the pause after you stop is the length of the last
 * phrase rather than the length of everything you said.
 */

type Phase = "idle" | "listening" | "settling" | "done" | "unsupported";

/** One spoken phrase, with the delay before the next begins. */
type Phrase = { text: string; hold: number };

const SCRIPT: Phrase[] = [
  { text: "So the migration touches about forty files,", hold: 1500 },
  { text: "which means it needs a proper review before Friday.", hold: 1700 },
  { text: "I'll put the benchmark numbers in the thread", hold: 1400 },
  { text: "so nobody has to take my word for it.", hold: 1500 },
];

/** How the raw decode reads before cleanup tidies it. */
const RAW =
  "so the migration touches about forty files which means it needs a proper review before friday i'll put the benchmark numbers in the thread so nobody has to take my word for it";

const CLEANED =
  "So the migration touches about forty files, which means it needs a proper review before Friday. I'll put the benchmark numbers in the thread so nobody has to take my word for it.";

const BARS = 28;

export function LiveDemo() {
  const reduceMotion = useReducedMotion();
  const [phase, setPhase] = useState<Phase>("idle");
  const [spoken, setSpoken] = useState(0);
  const [showCleaned, setShowCleaned] = useState(false);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  const clearTimers = useCallback(() => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  }, []);

  const later = useCallback((fn: () => void, ms: number) => {
    timers.current.push(setTimeout(fn, ms));
  }, []);

  const reset = useCallback(() => {
    clearTimers();
    setPhase("idle");
    setSpoken(0);
    setShowCleaned(false);
  }, [clearTimers]);

  useEffect(() => () => clearTimers(), [clearTimers]);

  const play = useCallback(() => {
    clearTimers();
    setSpoken(0);
    setShowCleaned(false);
    setPhase("listening");

    let elapsed = 0;
    SCRIPT.forEach((phrase, index) => {
      elapsed += phrase.hold;
      later(() => setSpoken(index + 1), elapsed);
    });
    // The tail is all that is left to decode once the speaker stops.
    later(() => setPhase("settling"), elapsed + 500);
    later(() => {
      setPhase("done");
      setShowCleaned(true);
    }, elapsed + 1500);
  }, [clearTimers, later]);

  const playUnsupported = useCallback(() => {
    clearTimers();
    setSpoken(0);
    setShowCleaned(false);
    setPhase("listening");
    later(() => setPhase("unsupported"), 2200);
  }, [clearTimers, later]);

  const listening = phase === "listening";
  const settled = SCRIPT.slice(0, spoken)
    .map((p) => p.text)
    .join(" ");

  return (
    <div className="w-full">
      {/* Controls */}
      <div className="mb-8 flex flex-wrap items-center justify-center gap-3">
        <button
          onClick={phase === "idle" || phase === "done" ? play : reset}
          className="group inline-flex items-center gap-2.5 rounded-full bg-ink px-6 py-3 text-sm font-medium text-paper transition-transform duration-200 hover:scale-[1.03] active:scale-[0.98]"
        >
          <span
            className={`inline-block h-2 w-2 rounded-full ${
              listening ? "bg-acid" : "bg-paper"
            }`}
          />
          {phase === "idle" || phase === "done"
            ? "Play the demo"
            : "Stop"}
        </button>
        <button
          onClick={playUnsupported}
          className="rounded-full border border-rule bg-transparent px-6 py-3 text-sm font-medium text-ink-soft transition-colors duration-200 hover:border-ink hover:text-ink"
        >
          Speak something else
        </button>
      </div>

      {/* The desktop scene */}
      <div className="relative mx-auto w-full max-w-3xl">
        <div className="relative overflow-hidden rounded-2xl border border-rule bg-paper-deep/60 p-4 shadow-[0_1px_0_rgba(255,255,255,0.6)_inset,0_20px_60px_-30px_rgba(20,20,15,0.4)] sm:rounded-3xl sm:p-8">
          {/* Faux document the text lands in */}
          <div className="min-h-[190px] rounded-xl border border-rule/70 bg-paper p-4 sm:min-h-[210px] sm:rounded-2xl sm:p-6">
            <div className="mb-4 flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-full bg-rule" />
              <span className="h-2.5 w-2.5 rounded-full bg-rule" />
              <span className="h-2.5 w-2.5 rounded-full bg-rule" />
              <span className="ml-2 font-mono text-[11px] uppercase tracking-widest text-ink-faint">
                message to the team
              </span>
            </div>

            <p className="text-pretty text-base leading-relaxed text-ink sm:text-lg">
              {phase === "unsupported" ? (
                <span className="text-ink-faint">
                  Waiting for English.
                </span>
              ) : showCleaned ? (
                <CleanedText text={CLEANED} reduceMotion={!!reduceMotion} />
              ) : settled ? (
                <>
                  <span>{settled}</span>
                  {listening && (
                    <span className="swar-caret ml-0.5 inline-block h-[1.1em] w-[2px] translate-y-[0.15em] bg-ink" />
                  )}
                </>
              ) : (
                <span className="text-ink-faint">
                  {listening
                    ? "Listening…"
                    : "Your cursor sits here. Press play."}
                </span>
              )}
            </p>

            {/* What settled versus what is still in flight */}
            {(listening || phase === "settling") && (
              <div className="mt-5 flex items-center gap-2 font-mono text-[11px] uppercase tracking-wider text-ink-faint">
                <span className="rounded-full bg-acid/70 px-2 py-0.5 text-ink">
                  {spoken} settled
                </span>
                <span>
                  {phase === "settling"
                    ? "decoding the last phrase"
                    : "transcribing as you speak"}
                </span>
              </div>
            )}
          </div>

          {/* The bar itself */}
          <div className="mt-6 flex justify-center sm:mt-8">
            <SwarBar
              phase={phase}
              reduceMotion={!!reduceMotion}
            />
          </div>
        </div>

        {/* The raw-versus-cleaned reveal */}
        <AnimatePresence>
          {showCleaned && (
            <motion.div
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.4, ease: [0.2, 0.8, 0.2, 1] }}
              className="mt-4 rounded-2xl border border-rule bg-paper/70 p-4 sm:p-5"
            >
              <div className="mb-2 font-mono text-[11px] uppercase tracking-widest text-ink-faint">
                what the model heard, before cleanup
              </div>
              <p className="text-sm leading-relaxed text-ink-faint">{RAW}</p>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

/** Fades the cleaned sentence in a word at a time, left to right. */
function CleanedText({
  text,
  reduceMotion,
}: {
  text: string;
  reduceMotion: boolean;
}) {
  const words = text.split(" ");
  return (
    <>
      {words.map((word, index) => (
        <motion.span
          key={`${word}-${index}`}
          initial={reduceMotion ? false : { opacity: 0.15 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.25, delay: reduceMotion ? 0 : index * 0.02 }}
          className="inline-block"
        >
          {word}
          {index < words.length - 1 ? " " : ""}
        </motion.span>
      ))}
    </>
  );
}

/**
 * The capsule. It stretches while listening, contracts while decoding, and
 * turns into a plain notice when the speech is not English.
 */
function SwarBar({
  phase,
  reduceMotion,
}: {
  phase: Phase;
  reduceMotion: boolean;
}) {
  const listening = phase === "listening";
  const unsupported = phase === "unsupported";

  return (
    <motion.div
      layout
      transition={
        reduceMotion
          ? { duration: 0 }
          : { type: "spring", stiffness: 260, damping: 26 }
      }
      className={`flex items-center gap-3 rounded-full border px-4 py-2.5 sm:gap-4 sm:px-5 sm:py-3 ${
        unsupported
          ? "border-ink/15 bg-ink text-paper"
          : "border-ink/10 bg-ink text-paper"
      }`}
      style={{ minWidth: unsupported ? undefined : 200 }}
    >
      <AnimatePresence mode="wait" initial={false}>
        {unsupported ? (
          <motion.div
            key="unsupported"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="flex items-center gap-2.5 whitespace-nowrap"
          >
            <span className="flex h-5 w-5 items-center justify-center rounded-full bg-violet text-[11px] font-bold text-ink">
              !
            </span>
            <span className="text-sm">
              That is not English. Swar only writes English.
            </span>
          </motion.div>
        ) : phase === "settling" ? (
          <motion.div
            key="settling"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="flex items-center gap-2.5 whitespace-nowrap"
          >
            <Spinner />
            <span className="text-sm">Finishing the last phrase</span>
          </motion.div>
        ) : phase === "done" ? (
          <motion.div
            key="done"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="flex items-center gap-2.5 whitespace-nowrap"
          >
            <span className="flex h-5 w-5 items-center justify-center rounded-full bg-acid text-[12px] font-bold text-ink">
              ✓
            </span>
            <span className="text-sm">Pasted at your cursor</span>
          </motion.div>
        ) : (
          <motion.div
            key="wave"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="flex items-center gap-3"
          >
            <Waveform active={listening} reduceMotion={reduceMotion} />
            <span className="font-mono text-[11px] uppercase tracking-widest text-paper/60">
              {listening ? "EN" : "hold ⌥"}
            </span>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

function Waveform({
  active,
  reduceMotion,
}: {
  active: boolean;
  reduceMotion: boolean;
}) {
  return (
    <div className="flex h-6 items-center gap-[3px]">
      {Array.from({ length: BARS }).map((_, index) => {
        // A fixed pseudo-random shape per bar keeps the waveform looking like
        // speech rather than an even oscillation, without any randomness that
        // would differ between server and client render.
        const seed = Math.abs(Math.sin(index * 12.9898) * 43758.5453);
        const base = 4 + (seed % 1) * 16;
        return (
          <motion.span
            key={index}
            className="w-[2px] rounded-full bg-paper"
            animate={
              active && !reduceMotion
                ? { height: [base * 0.35, base, base * 0.5, base * 0.85] }
                : { height: 3 }
            }
            transition={
              active && !reduceMotion
                ? {
                    duration: 0.7 + (seed % 1) * 0.5,
                    repeat: Infinity,
                    repeatType: "mirror",
                    ease: "easeInOut",
                  }
                : { duration: 0.25 }
            }
          />
        );
      })}
    </div>
  );
}

function Spinner() {
  return (
    <motion.span
      className="block h-4 w-4 rounded-full border-2 border-paper/25 border-t-acid"
      animate={{ rotate: 360 }}
      transition={{ duration: 0.8, repeat: Infinity, ease: "linear" }}
    />
  );
}
