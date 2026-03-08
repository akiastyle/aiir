#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function usage() {
  process.stderr.write(
    "usage: /var/www/aiir/server/scripts/aiir-oaiir-exec.sh <ingest-out-dir> [runtime-out-dir]\n"
  );
}

function readNdjson(file) {
  if (!fs.existsSync(file)) return [];
  const rows = fs.readFileSync(file, "utf8").split(/\r?\n/).filter(Boolean);
  const out = [];
  for (const line of rows) {
    try {
      out.push(JSON.parse(line));
    } catch {
      // Skip malformed rows to keep executor deterministic and resilient.
    }
  }
  return out;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function htmlRebuild(htmlOps) {
  const files = new Map();
  function state(file) {
    if (!files.has(file)) {
      files.set(file, { out: "", openTag: null, attrs: [] });
    }
    return files.get(file);
  }
  function flushOpen(st) {
    if (!st.openTag) return;
    const attrs = st.attrs.map((a) => ` ${a}=""`).join("");
    st.out += `<${st.openTag}${attrs}>`;
    st.openTag = null;
    st.attrs = [];
  }

  for (const op of htmlOps) {
    const file = op.file || "index.html";
    const st = state(file);
    if (op.op === 3000) {
      st.out = "";
      st.openTag = null;
      st.attrs = [];
      continue;
    }
    if (op.op === 3001) {
      flushOpen(st);
      st.openTag = String(op.tag || "div").toLowerCase();
      st.attrs = [];
      continue;
    }
    if (op.op === 3002) {
      if (st.openTag && op.attr) st.attrs.push(String(op.attr).toLowerCase());
      continue;
    }
    if (op.op === 3003) {
      flushOpen(st);
      st.out += String(op.text || "");
      continue;
    }
    if (op.op === 3004) {
      flushOpen(st);
      st.out += `</${String(op.tag || "div").toLowerCase()}>`;
    }
  }

  for (const st of files.values()) flushOpen(st);
  return files;
}

function cssRebuild(cssOps) {
  const bySelector = new Map();
  const atRules = [];
  let selector = null;
  for (const op of cssOps) {
    if (op.op === 3203 && op.value) {
      atRules.push(String(op.value));
      continue;
    }
    if (op.op === 3201) {
      selector = String(op.selector || "").trim();
      if (selector && !bySelector.has(selector)) bySelector.set(selector, []);
      continue;
    }
    if (op.op === 3202 && selector) {
      const prop = String(op.prop || "").trim();
      if (!prop) continue;
      const value = String(op.value || "").trim();
      bySelector.get(selector).push(`${prop}: ${value};`);
    }
  }
  let css = "";
  for (const v of atRules) css += `${v}\n`;
  for (const [sel, decls] of bySelector.entries()) {
    css += `${sel} {\n`;
    for (const d of decls) css += `  ${d}\n`;
    css += "}\n";
  }
  return css;
}

function jsRebuild(jsOps) {
  const lines = [];
  for (const op of jsOps) {
    if (op.op === 3300) continue;
    if (!op.value) continue;
    lines.push(String(op.value));
  }
  return lines.join("\n");
}

function injectAssets(html, css, js) {
  let out = html;
  const styleTag = css ? `<style>\n${css}\n</style>\n` : "";
  const scriptTag = js ? `<script>\n${js}\n</script>\n` : "";
  if (styleTag) {
    if (out.includes("</head>")) out = out.replace("</head>", `${styleTag}</head>`);
    else out = `${styleTag}${out}`;
  }
  if (scriptTag) {
    if (out.includes("</body>")) out = out.replace("</body>", `${scriptTag}</body>`);
    else out = `${out}\n${scriptTag}`;
  }
  return out;
}

function main() {
  const ingestOutDir = process.argv[2];
  const runtimeOutDir = process.argv[3] || path.join(ingestOutDir || "", "oaiir-runtime-web");
  if (!ingestOutDir) {
    usage();
    process.exit(1);
  }
  const reports = path.join(ingestOutDir, "reports");
  const htmlIr = path.join(reports, "oaiir-html-ir.ndjson");
  const cssIr = path.join(reports, "oaiir-css-ir.ndjson");
  const jsIr = path.join(reports, "oaiir-js-ir.ndjson");
  if (!fs.existsSync(htmlIr) && !fs.existsSync(cssIr) && !fs.existsSync(jsIr)) {
    process.stdout.write('{"ok":0,"err":"oaiir_ir_missing"}\n');
    process.exit(1);
  }

  const htmlOps = readNdjson(htmlIr);
  const cssOps = readNdjson(cssIr);
  const jsOps = readNdjson(jsIr);
  const rebuilt = htmlRebuild(htmlOps);
  const css = cssRebuild(cssOps);
  const js = jsRebuild(jsOps);

  const webOut = path.join(runtimeOutDir, "web");
  ensureDir(webOut);

  let fileCount = 0;
  for (const [rel, st] of rebuilt.entries()) {
    const outFile = path.join(webOut, rel);
    ensureDir(path.dirname(outFile));
    fs.writeFileSync(outFile, injectAssets(st.out, css, js), "utf8");
    fileCount += 1;
  }
  if (fileCount === 0) {
    const outFile = path.join(webOut, "index.html");
    fs.writeFileSync(
      outFile,
      injectAssets("<html><body><main>OAIIR runtime output</main></body></html>", css, js),
      "utf8"
    );
    fileCount = 1;
  }

  const manifest = {
    ok: 1,
    action: "oaiir_execute_web",
    ingest_out_dir: ingestOutDir,
    runtime_out_dir: runtimeOutDir,
    files_written: fileCount,
    html_ops: htmlOps.length,
    css_ops: cssOps.length,
    js_ops: jsOps.length,
  };
  fs.writeFileSync(path.join(runtimeOutDir, "manifest.json"), `${JSON.stringify(manifest)}\n`);
  process.stdout.write(`${JSON.stringify(manifest)}\n`);
}

main();
