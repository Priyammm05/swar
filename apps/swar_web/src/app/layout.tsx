import type { Metadata } from "next";
import { Fraunces, Inter } from "next/font/google";
import "./globals.css";

// Fraunces carries the display type. Its SOFT and WONK axes are what give the
// headline character on a page with no logo and no product photography.
const fraunces = Fraunces({
  variable: "--font-fraunces",
  subsets: ["latin"],
  axes: ["SOFT", "WONK", "opsz"],
});

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Swar · dictation that never leaves your machine",
  description:
    "Speak, and the words land where your cursor is. Swar transcribes on your machine. No upload, no account, no internet.",
  openGraph: {
    title: "Swar · dictation that never leaves your machine",
    description:
      "Speak, and the words land where your cursor is. Nothing is uploaded.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    // data-scroll-behavior: Next 16 stopped overriding scroll-behavior during
    // navigation unless asked, and this page relies on smooth anchor scrolling.
    <html
      lang="en"
      data-scroll-behavior="smooth"
      className={`${fraunces.variable} ${inter.variable} h-full`}
    >
      <body className="min-h-full font-sans antialiased">{children}</body>
    </html>
  );
}
