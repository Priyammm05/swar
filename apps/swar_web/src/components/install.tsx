"use client";

import { motion, useReducedMotion } from "motion/react";
import { useCallback, useEffect, useRef, useState } from "react";

import { SectionLabel } from "@/components/sections";

export const REPO_URL = "https://github.com/Priyammm05/swar";

/** GitHub's mark, inlined because the page loads nothing from another host. */
export function GitHubGlyph({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="currentColor" aria-hidden>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
    </svg>
  );
}

/**
 * How to actually get Swar running.
 *
 * There is no signed download to point at, so this section says so and gives
 * the real commands instead. Every step here is the one in the repository's
 * README; nothing is a plausible-looking placeholder.
 */

const NEEDS = [
  ["macOS", "10.15 or newer, Intel or Apple silicon"],
  ["Flutter", "3.35 or newer"],
  ["Rust", "1.88 or newer"],
  ["Bridge codegen", "flutter_rust_bridge_codegen 2.12.0"],
];

const CLONE = `git clone ${REPO_URL}.git
cd swar
./scripts/generate_bridge.sh`;

const RUN = `cd apps/swar_desktop
flutter run -d macos`;

const RELEASE = `flutter build macos --release
cd ../.. && ./scripts/sign_local_macos.sh`;

export function Install() {
  return (
    <section
      id="install"
      className="border-t border-rule px-5 py-24 sm:px-8 sm:py-32"
    >
      <div className="mx-auto max-w-5xl">
        <SectionLabel>run it yourself</SectionLabel>
        <h2 className="display-wonk max-w-2xl font-display text-[clamp(2rem,5.5vw,3.5rem)] leading-[1.03] text-ink">
          There is no download yet. Clone it and run it.
        </h2>
        <p className="mt-6 max-w-2xl text-pretty text-lg leading-relaxed text-ink-soft">
          No signed installer exists so far, so the honest answer is a build
          from source. It is MIT licensed, which means you can read every line
          that touches your microphone before you run it, and change any of it.
        </p>

        {/* min-w-0 on both columns is load-bearing. A grid item defaults to
            min-width:auto, so the widest command line set the column's floor
            and pushed the page 40px past a 390px phone instead of letting the
            code block scroll inside itself. */}
        <div className="mt-14 grid gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)] lg:gap-14">
          <div className="min-w-0">
            <h3 className="mb-6 font-mono text-[11px] uppercase tracking-widest text-ink-soft">
              what you need
            </h3>
            <dl className="space-y-4">
              {NEEDS.map(([name, detail]) => (
                <div key={name} className="flex gap-4">
                  <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-acid-deep" />
                  <div>
                    <dt className="font-medium text-ink">{name}</dt>
                    <dd className="text-sm leading-relaxed text-ink-soft">
                      {detail}
                    </dd>
                  </div>
                </div>
              ))}
            </dl>

            <a
              href={REPO_URL}
              target="_blank"
              rel="noreferrer noopener"
              className="mt-8 inline-flex items-center gap-2.5 rounded-full bg-ink px-6 py-3 text-sm font-medium text-paper transition-transform duration-200 hover:scale-[1.03] active:scale-[0.98]"
            >
              <GitHubGlyph className="h-4 w-4" />
              Open the repository
            </a>
          </div>

          <div className="min-w-0 space-y-4">
            <Step n="01" title="Clone and generate the bridge" code={CLONE} />
            <Step n="02" title="Run it" code={RUN} />
            <Step
              n="03"
              title="Or build a signed release"
              code={RELEASE}
              note="Signing with a stable local identity is what stops macOS asking for Accessibility permission again after every build."
            />
            <div className="rounded-2xl border border-rule bg-paper-deep/50 p-4 sm:p-5">
              <div className="mb-3 font-mono text-[11px] uppercase tracking-widest text-ink-faint">
                what the first launch downloads
              </div>
              <dl className="space-y-2 text-sm">
                {[
                  ["Parakeet", "639 MB", "The speech model. This is the one doing the work."],
                  ["Whisper small", "180 MB", "Fallback, for when the fast helper is unavailable."],
                  ["Qwen 3B", "1.96 GB", "Optional cleanup model. Fetched automatically today, which is more than most people want."],
                ].map(([name, size, why]) => (
                  <div key={name} className="flex flex-wrap items-baseline gap-x-2.5">
                    <dt className="font-medium text-ink">{name}</dt>
                    <dd className="font-mono text-xs font-medium text-moss">{size}</dd>
                    <dd className="w-full text-xs leading-relaxed text-ink-faint sm:w-auto sm:flex-1">
                      {why}
                    </dd>
                  </div>
                ))}
              </dl>
              <p className="mt-4 border-t border-rule pt-3 text-xs leading-relaxed text-ink-faint">
                2.8 GB in total. macOS will ask for Microphone and Accessibility
                permission on first run. After that Swar never touches the
                network again.
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function Step({
  n,
  title,
  code,
  note,
}: {
  n: string;
  title: string;
  code: string;
  note?: string;
}) {
  const reduceMotion = useReducedMotion();
  return (
    <motion.div
      initial={reduceMotion ? false : { opacity: 0, y: 16 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-60px" }}
      transition={{ duration: 0.45, ease: [0.2, 0.8, 0.2, 1] }}
      className="overflow-hidden rounded-2xl border border-rule bg-paper"
    >
      <div className="flex items-center gap-3 border-b border-rule px-4 py-3 sm:px-5">
        <span className="font-mono text-xs font-medium text-moss">{n}</span>
        <span className="text-sm font-medium text-ink">{title}</span>
        <CopyButton code={code} />
      </div>
      <pre className="overflow-x-auto px-4 py-4 text-[13px] leading-relaxed text-ink-soft sm:px-5">
        <code className="font-mono">{code}</code>
      </pre>
      {note && (
        <p className="border-t border-rule px-4 py-3 text-xs leading-relaxed text-ink-faint sm:px-5">
          {note}
        </p>
      )}
    </motion.div>
  );
}

function CopyButton({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => () => clearTimeout(timer.current), []);

  const copy = useCallback(() => {
    // Older Safari over plain http has no clipboard API. Failing quietly is
    // right here: the commands are selectable text either way.
    navigator.clipboard?.writeText(code).then(
      () => {
        setCopied(true);
        clearTimeout(timer.current);
        timer.current = setTimeout(() => setCopied(false), 1600);
      },
      () => undefined,
    );
  }, [code]);

  return (
    <button
      onClick={copy}
      className="ml-auto rounded-full border border-rule px-3 py-1 font-mono text-[10px] uppercase tracking-widest text-ink-faint transition-colors duration-200 hover:border-ink hover:text-ink"
    >
      {copied ? "copied" : "copy"}
    </button>
  );
}
