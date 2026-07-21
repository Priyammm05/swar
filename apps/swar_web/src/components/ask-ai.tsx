"use client";

import { REPO_URL } from "@/components/install";

/**
 * A closing strip that hands the page to an assistant.
 *
 * Each pill opens the service with the question already typed. The prompt
 * names the repository rather than this site, because the repository is the
 * thing that is actually published and reachable today.
 */

const PROMPT = `What is Swar? It is an open-source, fully offline dictation app for macOS that transcribes speech on-device with no server: ${REPO_URL} . Summarise what it does, how it works, and how it compares with cloud dictation tools.`;

const QUERY = encodeURIComponent(PROMPT);

/**
 * Prefill patterns, each the documented or widely used one for that service.
 * A service that changes or drops its parameter degrades to its own home page
 * with an empty box, which is a soft landing rather than an error.
 */
const DESTINATIONS = [
  { name: "ChatGPT", href: `https://chatgpt.com/?q=${QUERY}` },
  { name: "Claude", href: `https://claude.ai/new?q=${QUERY}` },
  { name: "Perplexity", href: `https://www.perplexity.ai/search?q=${QUERY}` },
  { name: "Google AI", href: `https://www.google.com/search?udm=50&q=${QUERY}` },
  { name: "Grok", href: `https://grok.com/?q=${QUERY}` },
];

export function AskAi() {
  return (
    <section className="bg-ink px-5 py-8 text-paper sm:px-8">
      <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-5 sm:flex-row sm:gap-8">
        <p className="flex items-center gap-2.5 font-mono text-[11px] uppercase tracking-[0.18em] text-paper/45">
          <Spark className="h-3.5 w-3.5" />
          Ask AI about Swar
        </p>

        <ul className="flex flex-wrap items-center justify-center gap-2 sm:justify-end sm:gap-2.5">
          {DESTINATIONS.map((destination) => (
            <li key={destination.name}>
              <a
                href={destination.href}
                target="_blank"
                rel="noreferrer noopener"
                className="group inline-flex items-center gap-2 rounded-full border border-paper/15 px-3.5 py-2 text-sm text-paper/70 transition-colors duration-200 hover:border-paper/40 hover:text-paper sm:px-4"
              >
                {destination.name}
                <ArrowOut className="h-3 w-3 opacity-40 transition-opacity duration-200 group-hover:opacity-90" />
              </a>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function Spark({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="currentColor" aria-hidden>
      <path d="M8 0.5 9.5 6.5 15.5 8 9.5 9.5 8 15.5 6.5 9.5 0.5 8 6.5 6.5Z" />
    </svg>
  );
}

function ArrowOut({ className = "" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 12 12"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M3.5 8.5 8.5 3.5M4.5 3.5h4v4" />
    </svg>
  );
}
