import crypto from "node:crypto";

const ALLOWED_TARGETS = {
  printers: "configs/printers",
  filaments: "configs/filaments",
  processes: "configs/processes",
  overlay: "configs/portable-overlay/root",
};

function json(res, status, payload) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(payload));
}

async function readJson(req) {
  let data = "";
  for await (const chunk of req) data += chunk;
  if (!data) return {};
  return JSON.parse(data);
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

async function ghRequest(path, { method = "GET", token, body } = {}) {
  const res = await fetch(`https://api.github.com${path}`, {
    method,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "User-Agent": "orca-config-admin",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
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
    if (req.method !== "POST") {
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

    const body = await readJson(req);
    const target = body.target;
    const basePath = ALLOWED_TARGETS[target];
    if (!basePath) {
      json(res, 400, { ok: false, error: "Invalid target" });
      return;
    }

    const requested = Array.isArray(body.paths) ? body.paths : [];
    if (!requested.length) {
      json(res, 400, { ok: false, error: "No paths provided" });
      return;
    }

    const commitMsg =
      (body.message && String(body.message).trim()) ||
      `Remove configs via admin (${target})`;

    const [owner, repo] = MIRROR_REPO.split("/");
    if (!owner || !repo) {
      json(res, 500, { ok: false, error: "Invalid MIRROR_REPO" });
      return;
    }

    const deletionPaths = new Set();
    for (const raw of requested) {
      const rel = sanitizePath(raw);
      if (!rel) continue;
      const fullPath = `${basePath}/${rel}`;
      const files = await listRecursive(owner, repo, GITHUB_PAT, fullPath);
      if (files.length) {
        for (const f of files) deletionPaths.add(f);
      } else {
        deletionPaths.add(fullPath);
      }
    }

    if (!deletionPaths.size) {
      json(res, 400, { ok: false, error: "No valid paths to delete" });
      return;
    }

    const ref = await ghRequest(`/repos/${owner}/${repo}/git/ref/heads/main`, {
      token: GITHUB_PAT,
    });
    const commitSha = ref.object.sha;
    const commit = await ghRequest(`/repos/${owner}/${repo}/git/commits/${commitSha}`, {
      token: GITHUB_PAT,
    });
    const baseTreeSha = commit.tree.sha;

    const treeItems = Array.from(deletionPaths).map((path) => ({
      path,
      mode: "100644",
      type: "blob",
      sha: null,
    }));

    const newTree = await ghRequest(`/repos/${owner}/${repo}/git/trees`, {
      method: "POST",
      token: GITHUB_PAT,
      body: {
        base_tree: baseTreeSha,
        tree: treeItems,
      },
    });

    const newCommit = await ghRequest(`/repos/${owner}/${repo}/git/commits`, {
      method: "POST",
      token: GITHUB_PAT,
      body: {
        message: commitMsg,
        tree: newTree.sha,
        parents: [commitSha],
      },
    });

    await ghRequest(`/repos/${owner}/${repo}/git/refs/heads/main`, {
      method: "PATCH",
      token: GITHUB_PAT,
      body: { sha: newCommit.sha },
    });

    json(res, 200, { ok: true, commit: newCommit.html_url || newCommit.sha });
  } catch (err) {
    json(res, 500, { ok: false, error: String(err && err.message ? err.message : err) });
  }
}
