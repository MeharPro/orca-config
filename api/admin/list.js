import crypto from "node:crypto";

const ALLOWED_TARGETS = {
  printers: "configs/printers",
  filaments: "configs/filaments",
  processes: "configs/processes",
};

function json(res, status, payload) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(payload));
}

function sanitizePath(p) {
  if (!p) return null;
  const normalized = p.replace(/\\/g, "/").replace(/^\/+/, "");
  if (normalized.includes("..")) return null;
  if (normalized.startsWith(".git")) return null;
  return normalized;
}

function safeEqual(input, secret) {
  if (typeof input !== "string" || typeof secret !== "string") return false;
  const a = Buffer.from(input, "utf8");
  const b = Buffer.from(secret, "utf8");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

async function ghRequest(path, { method = "GET", token } = {}) {
  const res = await fetch(`https://api.github.com${path}`, {
    method,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "User-Agent": "orca-config-admin",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`${path} -> ${res.status} ${text.slice(0, 200)}`);
  }
  return await res.json();
}

async function listRecursive(owner, repo, token, path) {
  const items = await ghRequest(`/repos/${owner}/${repo}/contents/${path}`, {
    token,
  });
  if (!Array.isArray(items)) return [];
  const output = [];
  for (const item of items) {
    if (item.type === "dir") {
      const nested = await listRecursive(owner, repo, token, item.path);
      output.push(...nested);
    } else if (item.type === "file") {
      output.push(item.path);
    }
  }
  return output;
}

export default async function handler(req, res) {
  try {
    if (req.method !== "GET") {
      json(res, 405, { ok: false, error: "Method not allowed" });
      return;
    }

    const {
      GITHUB_PAT,
      ADMIN_PASSWORD,
      MIRROR_REPO = "MeharPro/orca-config",
    } = process.env;

    if (!GITHUB_PAT) {
      json(res, 500, { ok: false, error: "Missing env var: GITHUB_PAT" });
      return;
    }
    if (!ADMIN_PASSWORD) {
      json(res, 500, { ok: false, error: "Missing env var: ADMIN_PASSWORD" });
      return;
    }

    const incomingPw =
      req.headers["x-admin-password"] ||
      req.headers["x-admin-secret"];
    if (!safeEqual(incomingPw, ADMIN_PASSWORD)) {
      json(res, 401, { ok: false, error: "Unauthorized" });
      return;
    }

    const target = sanitizePath(req.query && req.query.target);
    const basePath = ALLOWED_TARGETS[target];
    if (!basePath) {
      json(res, 400, { ok: false, error: "Invalid target" });
      return;
    }

    const [owner, repo] = MIRROR_REPO.split("/");
    if (!owner || !repo) {
      json(res, 500, { ok: false, error: "Invalid MIRROR_REPO" });
      return;
    }

    if (target === "printers") {
      const items = await ghRequest(`/repos/${owner}/${repo}/contents/${basePath}`, {
        token: GITHUB_PAT,
      });
      const profiles = Array.isArray(items)
        ? items.filter((item) => item.type === "dir").map((item) => item.name)
        : [];
      json(res, 200, { ok: true, target, profiles });
      return;
    }

    const files = await listRecursive(owner, repo, GITHUB_PAT, basePath);
    const profiles = files
      .filter((p) => p.startsWith(`${basePath}/`))
      .map((p) => p.slice(basePath.length + 1));

    json(res, 200, { ok: true, target, profiles });
  } catch (err) {
    json(res, 500, { ok: false, error: String(err && err.message ? err.message : err) });
  }
}
