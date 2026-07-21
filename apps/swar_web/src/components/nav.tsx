"use client";

import { motion, useMotionValueEvent, useScroll } from "motion/react";
import { useState } from "react";

import { SwarWordmark } from "@/components/mark";

export function Nav() {
  const { scrollY } = useScroll();
  const [lifted, setLifted] = useState(false);

  useMotionValueEvent(scrollY, "change", (value) => {
    setLifted(value > 24);
  });

  return (
    <header className="fixed inset-x-0 top-0 z-50 px-3 pt-3 sm:px-5 sm:pt-5">
      <motion.nav
        animate={{
          backgroundColor: lifted
            ? "rgba(242, 239, 228, 0.82)"
            : "rgba(242, 239, 228, 0)",
          borderColor: lifted ? "rgba(220, 213, 194, 1)" : "rgba(220, 213, 194, 0)",
        }}
        transition={{ duration: 0.25 }}
        className="mx-auto flex max-w-5xl items-center justify-between rounded-full border px-4 py-2.5 backdrop-blur-md sm:px-5"
      >
        <a
          href="#top"
          className="font-display text-xl tracking-tight text-ink sm:text-2xl"
        >
          <SwarWordmark />
        </a>
        <div className="flex items-center gap-1.5 sm:gap-2">
          <a
            href="#why"
            className="hidden rounded-full px-3.5 py-2 text-sm text-ink-soft transition-colors hover:text-ink sm:block"
          >
            Why
          </a>
          <a
            href="#supported"
            className="hidden rounded-full px-3.5 py-2 text-sm text-ink-soft transition-colors hover:text-ink sm:block"
          >
            What it does
          </a>
          <a
            href="#demo"
            className="rounded-full bg-ink px-4 py-2 text-sm font-medium text-paper transition-transform duration-200 hover:scale-[1.04] active:scale-[0.98] sm:px-5"
          >
            See it work
          </a>
        </div>
      </motion.nav>
    </header>
  );
}
