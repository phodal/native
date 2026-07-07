import createMDX from "@next/mdx";

const withMDX = createMDX({
  options: {
    // Plugin named as a string so the config stays serializable for
    // Turbopack. GFM is what gives .mdx pages pipe tables (plus autolinks
    // and strikethrough) — without it, table markdown renders as a plain
    // paragraph of pipes.
    remarkPlugins: [["remark-gfm"]],
  },
});

/** @type {import('next').NextConfig} */
const nextConfig = {
  pageExtensions: ["ts", "tsx", "md", "mdx"],
  // CI-style builds set NEXT_DIST_DIR so `pnpm check` never shares .next
  // with a running dev server (a shared dist dir corrupts the dev cache).
  distDir: process.env.NEXT_DIST_DIR || ".next",
  async redirects() {
    return [
      // The Philosophy page became the Introduction, the opening page of the docs.
      { source: "/philosophy", destination: "/introduction", permanent: true },
    ];
  },
};

export default withMDX(nextConfig);
