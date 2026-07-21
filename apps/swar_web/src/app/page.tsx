import { Hero } from "@/components/hero";
import { Install } from "@/components/install";
import { LiveDemo } from "@/components/live-demo";
import { Nav } from "@/components/nav";
import {
  Cta,
  Footer,
  HowItWorks,
  Numbers,
  Privacy,
  SectionLabel,
  Supported,
  Why,
} from "@/components/sections";

export default function Home() {
  return (
    <>
      <Nav />
      <main id="top">
        <Hero />

        <section
          id="demo"
          className="border-t border-rule px-5 py-24 sm:px-8 sm:py-32"
        >
          <div className="mx-auto max-w-5xl">
            <div className="mb-12 text-center sm:mb-14">
              <SectionLabel>the bar, on the web</SectionLabel>
              <h2 className="display-wonk mx-auto max-w-2xl font-display text-[clamp(2rem,5.5vw,3.5rem)] leading-[1.03] text-ink">
                Watch the words settle before you stop talking.
              </h2>
              <p className="mx-auto mt-6 max-w-xl text-pretty leading-relaxed text-ink-soft">
                Most dictation waits for silence and then thinks. Swar finishes
                each phrase as you pause, so the only thing left when you let go
                is the last one.
              </p>
            </div>
            <LiveDemo />
          </div>
        </section>

        <div id="why">
          <Why />
        </div>
        <HowItWorks />
        <Numbers />
        <div id="supported">
          <Supported />
        </div>
        <Privacy />
        <Install />
        <Cta />
      </main>
      <Footer />
    </>
  );
}
