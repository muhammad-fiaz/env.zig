import { defineConfig } from "vitepress";
import llmstxt from "vitepress-plugin-llms";

// Site configuration
export const SITE_URL = "https://muhammad-fiaz.github.io/env.zig";
export const SITE_NAME = "env.zig";
export const SITE_DESCRIPTION = "A production-grade runtime .env library for Zig with parsing, interpolation, validation, serialization, schema validation, type-safe accessors, and modular architecture.";

// Google Analytics and Google Tag Manager IDs
export const GA_ID = "G-6BVYCRK57P";
export const GTM_ID = "GTM-P4M9T8ZR";

// Google AdSense Client ID
export const ADSENSE_CLIENT_ID = "ca-pub-2040560600290490";

// SEO Keywords
export const KEYWORDS = "zig, env, dotenv, environment, configuration, .env, interpolation, validation, serialization, schema, parser, lexer, type-safe, allocator, zig 0.16";

export default defineConfig({
  lang: "en-US",
  title: SITE_NAME,
  description: SITE_DESCRIPTION,
  lastUpdated: true,
  cleanUrls: true,
  base: "/env.zig/",

  sitemap: {
    hostname: SITE_URL,
  },

  vite: {
    plugins: [llmstxt()],
  },

  head: [
    // Primary Meta Tags
    ["meta", { name: "title", content: SITE_NAME }],
    ["meta", { name: "description", content: SITE_DESCRIPTION }],
    ["meta", { name: "keywords", content: KEYWORDS }],
    ["meta", { name: "author", content: "Muhammad Fiaz" }],
    ["meta", { name: "publisher", content: "Muhammad Fiaz" }],
    ["meta", { name: "robots", content: "index, follow" }],
    ["meta", { name: "language", content: "English" }],
    ["meta", { name: "revisit-after", content: "7 days" }],
    ["meta", { name: "generator", content: "VitePress" }],

    // Open Graph
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:url", content: SITE_URL }],
    ["meta", { property: "og:title", content: SITE_NAME }],
    ["meta", { property: "og:description", content: SITE_DESCRIPTION }],
    ["meta", { property: "og:image", content: `${SITE_URL}/cover.png` }],
    ["meta", { property: "og:image:width", content: "1200" }],
    ["meta", { property: "og:image:height", content: "630" }],
    ["meta", { property: "og:image:alt", content: "env.zig - Runtime .env Library for Zig" }],
    ["meta", { property: "og:image:secure_url", content: `${SITE_URL}/cover.png` }],
    ["meta", { property: "og:site_name", content: SITE_NAME }],
    ["meta", { property: "og:locale", content: "en_US" }],

    // Twitter Card
    ["meta", { name: "twitter:card", content: "summary_large_image" }],
    ["meta", { name: "twitter:url", content: SITE_URL }],
    ["meta", { name: "twitter:title", content: SITE_NAME }],
    ["meta", { name: "twitter:description", content: SITE_DESCRIPTION }],
    ["meta", { name: "twitter:image", content: `${SITE_URL}/cover.png` }],
    ["meta", { name: "twitter:image:alt", content: "env.zig - Runtime .env Library for Zig" }],
    ["meta", { name: "twitter:site", content: "@muhammadfiaz_" }],
    ["meta", { name: "twitter:creator", content: "@muhammadfiaz_" }],

    // Canonical URL
    ["link", { rel: "canonical", href: SITE_URL }],

    // Favicons
    ["link", { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" }],

    // Theme color
    ["meta", { name: "theme-color", content: "#f7a41d" }],
    ["meta", { name: "msapplication-TileColor", content: "#f7a41d" }],

    // Google Analytics
    [
      "script",
      { async: "", src: `https://www.googletagmanager.com/gtag/js?id=${GA_ID}` },
    ],
    [
      "script",
      {},
      `window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());
gtag('config', '${GA_ID}');`,
    ],

    // Google Tag Manager
    ...(GTM_ID
      ? ([
          [
            "script",
            {},
            `(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start': new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0], j=d.createElement(s), dl=l!='dataLayer'?'&l='+l:''; j.async=true; j.src='https://www.googletagmanager.com/gtm.js?id='+i+dl; f.parentNode.insertBefore(j,f);})(window,document,'script','dataLayer','${GTM_ID}');`,
          ],
          [
            "noscript",
            {},
            `<iframe src="https://www.googletagmanager.com/ns.html?id=${GTM_ID}" height="0" width="0" style="display:none;visibility:hidden"></iframe>`,
          ],
        ] as [string, Record<string, string>, string][])
      : []),

    // Google AdSense
    [
      "script",
      {
        async: "",
        src: `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${ADSENSE_CLIENT_ID}`,
        crossorigin: "anonymous",
      },
    ],
  ],

  ignoreDeadLinks: [/.*\.zig$/],

  transformPageData(pageData: any) {
    const pageTitle = pageData.title || SITE_NAME;
    const pageDescription = pageData.description || SITE_DESCRIPTION;
    const normalizedPath = pageData.relativePath
      .replace(/\.md$/, "")
      .replace(/(^|\/)index$/, "$1")
      .replace(/\/$/, "");
    const canonicalUrl = normalizedPath.length > 0 ? `${SITE_URL}/${normalizedPath}` : SITE_URL;

    pageData.frontmatter.head ??= [];
    pageData.frontmatter.head.push(
      ["link", { rel: "canonical", href: canonicalUrl }],
      ["meta", { property: "og:title", content: `${pageTitle} | ${SITE_NAME}` }],
      ["meta", { property: "og:url", content: canonicalUrl }]
    );

    if (pageData.frontmatter.description) {
      pageData.frontmatter.head.push(
        ["meta", { property: "og:description", content: pageData.frontmatter.description }],
        ["meta", { name: "description", content: pageData.frontmatter.description }]
      );
    }

    // Dynamic JSON-LD Schema
    const isHome = pageData.relativePath === "index.md";
    const lastUpdated = pageData.lastUpdated
      ? new Date(pageData.lastUpdated).toISOString()
      : new Date().toISOString();

    const graph: any[] = [];

    // WebSite Schema (Home only)
    if (isHome) {
      graph.push({
        "@type": "WebSite",
        "name": SITE_NAME,
        "url": SITE_URL,
        "description": SITE_DESCRIPTION,
        "author": {
          "@type": "Person",
          "name": "Muhammad Fiaz",
          "url": "https://github.com/muhammad-fiaz"
        }
      });
    }

    // Author Schema
    const authorSchema = {
      "@type": "Person",
      "name": "Muhammad Fiaz",
      "url": "https://muhammadfiaz.com",
      "sameAs": [
        "https://github.com/muhammad-fiaz",
        "https://www.linkedin.com/in/muhammad-fiaz-",
        "https://x.com/muhammadfiaz_"
      ]
    };

    // Main Entity Schema
    const primarySchema: Record<string, any> = {
      "@type": isHome ? "SoftwareApplication" : "TechArticle",
      "name": isHome ? SITE_NAME : pageTitle,
      "description": pageDescription,
      "url": canonicalUrl,
      "image": `${SITE_URL}/cover.png`,
      "author": authorSchema,
      "publisher": {
        "@type": "Person",
        "name": "Muhammad Fiaz",
        "url": "https://muhammadfiaz.com"
      }
    };

    if (isHome) {
      Object.assign(primarySchema, {
        "applicationCategory": "DeveloperApplication",
        "operatingSystem": "Cross-platform",
        "programmingLanguage": "Zig",
        "offers": {
          "@type": "Offer",
          "price": "0",
          "priceCurrency": "USD"
        },
        "downloadUrl": "https://github.com/muhammad-fiaz/env.zig",
        "softwareVersion": "0.0.1",
        "license": "https://opensource.org/licenses/MIT"
      });
    } else {
      const pathParts = pageData.relativePath.split("/");
      const section = pathParts.length > 1
        ? pathParts[0].charAt(0).toUpperCase() + pathParts[0].slice(1)
        : "Documentation";

      Object.assign(primarySchema, {
        "headline": pageTitle,
        "articleSection": section,
        "mainEntityOfPage": {
          "@type": "WebPage",
          "@id": canonicalUrl
        },
        "datePublished": "2026-07-03T00:00:00Z",
        "dateModified": lastUpdated
      });
    }
    graph.push(primarySchema);

    // BreadcrumbList Schema
    const breadcrumbs: any[] = [
      {
        "@type": "ListItem",
        "position": 1,
        "name": "Home",
        "item": SITE_URL
      }
    ];

    if (!isHome) {
      const pathParts = pageData.relativePath.replace(/\.md$/, "").split("/");
      let currentPath = SITE_URL;

      pathParts.forEach((part: string, index: number) => {
        currentPath += `/${part}`;
        const name = part.split("-").map(s => s.charAt(0).toUpperCase() + s.slice(1)).join(" ");

        breadcrumbs.push({
          "@type": "ListItem",
          "position": index + 2,
          "name": name,
          "item": index === pathParts.length - 1 ? canonicalUrl : currentPath
        });
      });
    }

    graph.push({
      "@type": "BreadcrumbList",
      "itemListElement": breadcrumbs
    });

    pageData.frontmatter.head.push([
      "script",
      { type: "application/ld+json" },
      JSON.stringify({
        "@context": "https://schema.org",
        "@graph": graph
      })
    ]);
  },

  themeConfig: {
    logo: "/logo.png",
    siteTitle: SITE_NAME,

    nav: [
      { text: "Home", link: "/" },
      { text: "Guide", link: "/guide/getting-started" },
      { text: "API", link: "/api/env" },
      { text: "Examples", link: "/examples/" },
      { text: "Comparison", link: "/comparison" },
      {
        text: "Support",
        items: [
          { text: "Sponsor", link: "https://github.com/sponsors/muhammad-fiaz" },
          { text: "Donate", link: "https://pay.muhammadfiaz.com" },
        ],
      },
      { text: "GitHub", link: "https://github.com/muhammad-fiaz/env.zig" },
    ],

    sidebar: [
      {
        text: "Introduction",
        items: [
          { text: "Getting Started", link: "/guide/getting-started" },
          { text: "Configuration", link: "/guide/configuration" },
          { text: "Comparison", link: "/comparison" },
        ],
      },
      {
        text: "Guide",
        items: [
          { text: "Interpolation", link: "/guide/interpolation" },
          { text: "Clone & Merge", link: "/guide/clone-merge" },
          { text: "Cache", link: "/guide/cache" },
          { text: "Iterator", link: "/guide/iterator" },
          { text: "Validation", link: "/guide/validation" },
          { text: "Serialization", link: "/guide/serialization" },
        ],
      },
      {
        text: "Examples",
        items: [
          { text: "Overview", link: "/examples/" },
          { text: "Basic", link: "/examples/basic" },
          { text: "Interpolation", link: "/examples/interpolation" },
          { text: "Clone & Merge", link: "/examples/clone-merge" },
          { text: "Cache", link: "/examples/cache" },
          { text: "Iterator", link: "/examples/iterator" },
          { text: "Validation", link: "/examples/validation" },
          { text: "Serialization", link: "/examples/serialization" },
        ],
      },
      {
        text: "API Reference",
        items: [
          { text: "Env", link: "/api/env" },
          { text: "Schema", link: "/api/schema" },
          { text: "Config", link: "/api/config" },
          { text: "Validators", link: "/api/validators" },
        ],
      },
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/muhammad-fiaz/env.zig" },
      { icon: "linkedin", link: "https://www.linkedin.com/in/muhammad-fiaz-" },
      { icon: "x", link: "https://x.com/muhammadfiaz_" },
    ],

    footer: {
      message: "Released under the MIT License.",
      copyright: "Copyright © 2024-2026 Muhammad Fiaz",
    },

    search: {
      provider: "local",
    },

    editLink: {
      pattern: "https://github.com/muhammad-fiaz/env.zig/edit/main/docs/:path",
      text: "Edit this page on GitHub",
    },

    lastUpdated: {
      text: "Last updated",
      formatOptions: {
        dateStyle: "medium",
        timeStyle: "short",
      },
    },

    outline: {
      level: [2, 3],
      label: "On this page",
    },

    docFooter: {
      prev: "Previous",
      next: "Next",
    },

    returnToTopLabel: "Return to top",
    sidebarMenuLabel: "Menu",
    darkModeSwitchLabel: "Appearance",
    lightModeSwitchTitle: "Switch to dark mode",
    darkModeSwitchTitle: "Switch to light mode",
  },
});
