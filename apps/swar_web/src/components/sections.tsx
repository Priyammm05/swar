"use client";

import { motion, useReducedMotion } from "motion/react";
import type { ReactNode } from "react";

/**
 * Every number on this page comes from the project's own benchmark corpus:
 * 986 saved English passages, 20 to 900 words, scored on the shipping engine.
 * Nothing here is estimated, and there are no testimonials, because there are
 * no users yet to quote.
 */

function Reveal({
  children,
  delay = 0,
}: {
  children: ReactNode;
  delay?: number;
}) {
  const reduceMotion = useReducedMotion();
  return (
    <motion.div
      initial={reduceMotion ? false : { opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={{ duration: 0.55, delay, ease: [0.2, 0.8, 0.2, 1] }}
    >
      {children}
    </motion.div>
  );
}

export function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <p className="mb-5 font-mono text-[11px] uppercase tracking-widest text-ink-faint">
      {children}
    </p>
  );
}

export function Why() {
  return (
    <section className="border-t border-rule px-5 py-24 sm:px-8 sm:py-32">
      <div className="mx-auto max-w-5xl">
        <Reveal>
          <SectionLabel>the trade every other one makes</SectionLabel>
          <h2 className="display-wonk max-w-3xl font-display text-[clamp(2rem,5.5vw,3.75rem)] leading-[1.02] text-ink">
            Good dictation usually means sending your voice to someone
            else&apos;s computer.
          </h2>
          <p className="mt-7 max-w-2xl text-pretty text-lg leading-relaxed text-ink-soft">
            That is the deal on offer nearly everywhere. Your microphone goes to
            a server, the text comes back, and you take it on faith that the
            recording was discarded. For a grocery list, fine. For a salary
            conversation, a medical note, an unannounced product, or anything
            under NDA, it is a real decision you have to make every time you
            hold the key.
          </p>
          <p className="mt-5 max-w-2xl text-pretty text-lg leading-relaxed text-ink">
            Swar does not ask you to make it. The model sits on your disk. The
            audio never has anywhere to go.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

export function HowItWorks() {
  const steps = [
    {
      n: "01",
      title: "Hold the key",
      body: "A bar appears above whatever you are working in. It never takes focus, so your cursor stays exactly where you left it.",
    },
    {
      n: "02",
      title: "Keep talking",
      body: "Swar transcribes as you go. Each phrase is settled the moment you pause, rather than piling up until you stop.",
    },
    {
      n: "03",
      title: "Let go",
      body: "Only the last phrase is still being decoded, so the wait is roughly the same whether you spoke for ten seconds or two minutes.",
    },
  ];

  return (
    <section className="border-t border-rule bg-paper-deep/40 px-5 py-24 sm:px-8 sm:py-32">
      <div className="mx-auto max-w-5xl">
        <Reveal>
          <SectionLabel>how it works</SectionLabel>
          <h2 className="display-wonk max-w-2xl font-display text-[clamp(2rem,5.5vw,3.5rem)] leading-[1.03] text-ink">
            Three steps, and one of them is just talking.
          </h2>
        </Reveal>

        <div className="mt-14 grid gap-8 sm:mt-16 md:grid-cols-3">
          {steps.map((step, index) => (
            <Reveal key={step.n} delay={index * 0.08}>
              <div className="h-full rounded-2xl border border-rule bg-paper p-7">
                <div className="mb-5 font-mono text-sm text-acid-deep">
                  {step.n}
                </div>
                <h3 className="mb-3 font-display text-2xl text-ink">
                  {step.title}
                </h3>
                <p className="text-pretty leading-relaxed text-ink-soft">
                  {step.body}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

export function Numbers() {
  const stats = [
    {
      value: "92%",
      label: "of words correct",
      note: "Across 986 saved passages, 20 to 900 words each.",
    },
    {
      value: "4.3s",
      label: "to transcribe 38 seconds",
      note: "Measured warm, on an M-series Mac.",
    },
    {
      value: "0",
      label: "bytes uploaded",
      note: "There is no server to upload to.",
    },
  ];

  return (
    <section className="border-t border-rule px-5 py-24 sm:px-8 sm:py-32">
      <div className="mx-auto max-w-5xl">
        <Reveal>
          <SectionLabel>measured, not claimed</SectionLabel>
        </Reveal>
        <div className="grid gap-10 sm:grid-cols-3 sm:gap-8">
          {stats.map((stat, index) => (
            <Reveal key={stat.label} delay={index * 0.08}>
              <div>
                <div className="display-wonk font-display text-[clamp(3rem,8vw,4.5rem)] leading-none text-ink">
                  {stat.value}
                </div>
                <div className="mt-3 text-base font-medium text-ink">
                  {stat.label}
                </div>
                <div className="mt-1.5 text-sm leading-relaxed text-ink-faint">
                  {stat.note}
                </div>
              </div>
            </Reveal>
          ))}
        </div>
        <Reveal delay={0.2}>
          <p className="mt-12 max-w-2xl border-l-2 border-rule pl-5 text-sm leading-relaxed text-ink-faint">
            These come from our own benchmark corpus, and the speech in it is
            synthesised rather than recorded from people. It is a fair way to
            compare one build against the next. It is not yet a promise about
            how Swar handles your particular voice, room, or microphone.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

export function Supported() {
  const yes = [
    ["English", "The only language Swar writes."],
    ["macOS", "Apple silicon and Intel."],
    ["Any app", "Native, browser, or Electron."],
    ["Three styles", "Verbatim, tidied, or rewritten for intent."],
    ["Your vocabulary", "Names and jargon you add, spelled right."],
    ["Fully offline", "Works on a plane, in a basement, on a locked-down laptop."],
  ];

  const notYet = [
    ["Hindi and Hinglish", "Removed for now. It was not good enough to ship."],
    ["Windows and Linux", "Not started."],
    ["iPhone and Android", "Not started."],
    ["Sync between devices", "There is no server, so there is nothing to sync through."],
  ];

  return (
    <section className="border-t border-rule bg-paper-deep/40 px-5 py-24 sm:px-8 sm:py-32">
      <div className="mx-auto max-w-5xl">
        <Reveal>
          <SectionLabel>what it does and does not do</SectionLabel>
          <h2 className="display-wonk max-w-2xl font-display text-[clamp(2rem,5.5vw,3.5rem)] leading-[1.03] text-ink">
            A short list, honestly kept.
          </h2>
        </Reveal>

        <div className="mt-14 grid gap-12 md:grid-cols-2 md:gap-16">
          <Reveal>
            <h3 className="mb-6 font-mono text-[11px] uppercase tracking-widest text-ink-soft">
              works today
            </h3>
            <ul className="space-y-5">
              {yes.map(([title, body]) => (
                <li key={title} className="flex gap-4">
                  <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-acid-deep" />
                  <div>
                    <div className="font-medium text-ink">{title}</div>
                    <div className="text-sm leading-relaxed text-ink-soft">
                      {body}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </Reveal>

          <Reveal delay={0.1}>
            <h3 className="mb-6 font-mono text-[11px] uppercase tracking-widest text-ink-soft">
              does not, yet
            </h3>
            <ul className="space-y-5">
              {notYet.map(([title, body]) => (
                <li key={title} className="flex gap-4">
                  <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full border border-ink-faint" />
                  <div>
                    <div className="font-medium text-ink-soft">{title}</div>
                    <div className="text-sm leading-relaxed text-ink-faint">
                      {body}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </Reveal>
        </div>
      </div>
    </section>
  );
}

export function Privacy() {
  return (
    <section className="border-t border-rule px-5 py-24 sm:px-8 sm:py-32">
      <div className="mx-auto max-w-3xl text-center">
        <Reveal>
          <SectionLabel>the part people ask about</SectionLabel>
          <h2 className="display-wonk font-display text-[clamp(2rem,6vw,4rem)] leading-[1.02] text-ink">
            There is no server.
          </h2>
          <p className="mx-auto mt-7 max-w-xl text-pretty text-lg leading-relaxed text-ink-soft">
            Not a private one. Not an encrypted one. None. The model file is on
            your disk, the transcription runs in a process on your machine, and
            the recording is overwritten in memory as soon as the words are
            written out.
          </p>
          <p className="mx-auto mt-5 max-w-xl text-pretty text-lg leading-relaxed text-ink">
            Turn off your wifi and use it exactly as before. That is the whole
            test, and it is the one we care about passing.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

export function Cta() {
  return (
    <section className="border-t border-rule px-5 py-24 sm:px-8 sm:py-32">
      <div className="mx-auto max-w-3xl text-center">
        <Reveal>
          <h2 className="display-wonk font-display text-[clamp(2.25rem,7vw,4.5rem)] leading-[1] text-ink">
            Stop typing what you could just say.
          </h2>
          <div className="mt-10 flex flex-col items-center gap-4">
            <a
              href="#demo"
              className="inline-flex items-center gap-3 rounded-full bg-ink px-9 py-4 text-base font-medium text-paper transition-transform duration-200 hover:scale-[1.03] active:scale-[0.98]"
            >
              Try the demo
            </a>
            <p className="font-mono text-[11px] uppercase tracking-widest text-ink-faint">
              macOS · English · free while in beta
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

export function Footer() {
  return (
    <footer className="border-t border-rule px-5 py-12 sm:px-8">
      <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-5 sm:flex-row">
        <span className="font-display text-2xl tracking-tight text-ink">
          swar
        </span>
        <p className="text-center text-sm text-ink-faint sm:text-right">
          Dictation that runs on your own machine.
        </p>
      </div>
    </footer>
  );
}
