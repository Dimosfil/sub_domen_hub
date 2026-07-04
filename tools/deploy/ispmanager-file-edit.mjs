#!/usr/bin/env node
import { readFile } from "node:fs/promises";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const key = process.argv[index];
  const value = process.argv[index + 1];
  if (!key.startsWith("--") || value === undefined || value.startsWith("--")) {
    throw new Error(`Expected --key value argument near ${key}`);
  }
  args.set(key.slice(2), value);
  index += 1;
}

const panelUrl = args.get("panel-url") || "https://server15.hosting.reg.ru:1500/ispmgr";
const remotePath = args.get("remote");
const localPath = args.get("local");
const userEnv = args.get("user-env") || "SUB_DOMEN_HUB_PANEL_USER";
const passwordEnv = args.get("password-env") || "SUB_DOMEN_HUB_PANEL_PASSWORD";
const expectMarker = args.get("expect") || "";

if (!remotePath || !localPath) {
  throw new Error("Usage: node tools/deploy/ispmanager-file-edit.mjs --local path --remote /remote/file");
}

const panelUser = process.env[userEnv];
const panelPassword = process.env[passwordEnv];
if (!panelUser || !panelPassword) {
  throw new Error(`Missing ${userEnv} or ${passwordEnv}.`);
}

async function callPanel(params) {
  const body = new URLSearchParams({
    authinfo: `${panelUser}:${panelPassword}`,
    out: "json",
    ...params,
  });

  const response = await fetch(panelUrl, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded; charset=utf-8",
    },
    body,
  });

  if (!response.ok) {
    throw new Error(`ISPmanager HTTP ${response.status}: ${await response.text()}`);
  }

  const data = await response.json();
  if (data?.doc?.error) {
    throw new Error(data.doc.error?.msg?.$ || JSON.stringify(data.doc.error));
  }
  return data;
}

const content = await readFile(localPath, "utf8");
await callPanel({
  func: "file.edit",
  sok: "ok",
  elid: remotePath,
  encoding: "UTF-8",
  fdata: content,
});

const readback = await callPanel({
  func: "file.edit",
  elid: remotePath,
});

const saved = readback?.doc?.fdata?.$ || "";
if (saved.includes("????") || saved.includes("\uFFFD") || /Р[ ЎІЃЋ]/.test(saved)) {
  throw new Error("Readback contains likely encoding corruption.");
}

if (expectMarker && !saved.includes(expectMarker)) {
  throw new Error("Readback does not contain expected marker.");
}

console.log(`Uploaded and verified ${remotePath}`);
