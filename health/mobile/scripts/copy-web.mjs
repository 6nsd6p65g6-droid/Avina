// Copies the web app from ../ into www/ and marks the distribution channel.
// AVINA_CHANNEL: play | appstore (store rules: no outside payments) | direct (APK from your site: all payment methods)
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, "..", "..");
const out = join(here, "..", "www");
const channel = process.env.AVINA_CHANNEL || "direct";
if (!["play", "appstore", "direct"].includes(channel)) throw new Error("AVINA_CHANNEL must be play, appstore or direct");

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
for (const f of ["manifest.json", "sw.js", "privacy.html", "terms.html", "icon-192.png", "icon-512.png", "icon-maskable-512.png", "apple-touch-icon.png", "favicon-32.png"]) {
  cpSync(join(src, f), join(out, f));
}
const html = readFileSync(join(src, "index.html"), "utf8");
const tag = `<script>window.AVINA_CHANNEL=${JSON.stringify(channel)}</script>`;
if (!html.includes("</head>")) throw new Error("index.html has no </head>");
writeFileSync(join(out, "index.html"), html.replace("</head>", tag + "\n</head>"));
console.log(`www/ ready (channel: ${channel})`);
