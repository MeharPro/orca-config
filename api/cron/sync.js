// Vercel Cron endpoint:
// - Checks OrcaSlicer upstream latest release tag
// - If our repo doesn't have that tag as a GitHub Release, dispatches the GitHub Actions workflow
//
// Required Vercel env var:
// - GITHUB_PAT: GitHub Personal Access Token with permission to dispatch workflows on MeharPro/orca-config
//
// Optional env var:
// - CRON_SECRET: if set, requests must include ?secret=... OR header x-cron-secret: ...
// - UPSTREAM_REPO (default: OrcaSlicer/OrcaSlicer)
// - MIRROR_REPO (default: MeharPro/orca-config)
// - WORKFLOW_FILE (default: sync-orcaslicer-release.yml)

export default async function handler(req, res) {
  try {
    const {
      GITHUB_PAT,
      CRON_SECRET,
      UPSTREAM_REPO = "OrcaSlicer/OrcaSlicer",
      MIRROR_REPO = "MeharPro/orca-config",
      WORKFLOW_FILE = "sync-orcaslicer-release.yml",
    } = process.env;

    if (!GITHUB_PAT) {
      res.status(500).json({ ok: false, error: "Missing env var: GITHUB_PAT" });
      return;
    }

    if (CRON_SECRET) {
      const secret =
        (req.query && req.query.secret) ||
        req.headers["x-cron-secret"] ||
        req.headers["x-vercel-cron-secret"];
      if (secret !== CRON_SECRET) {
        res.status(401).json({ ok: false, error: "Unauthorized" });
        return;
      }
    }

    const ghHeaders = {
      Accept: "application/vnd.github+json",
      "User-Agent": "orca-config-vercel-cron",
      Authorization: `Bearer ${GITHUB_PAT}`,
      "X-GitHub-Api-Version": "2022-11-28",
    };

    async function fetchJson(url) {
      const r = await fetch(url, { headers: ghHeaders, cache: "no-store" });
      if (!r.ok) {
        const body = await r.text().catch(() => "");
        throw new Error(`${url} -> ${r.status} ${body.slice(0, 200)}`);
      }
      return await r.json();
    }

    // 1) Determine upstream latest tag
    const upstream = await fetchJson(`https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest`);
    const tag = (upstream && upstream.tag_name) || "";
    if (!tag) throw new Error("Upstream did not return tag_name");

    // 2) Check if mirror repo already has this GitHub Release
    let mirrorHasRelease = true;
    try {
      await fetchJson(`https://api.github.com/repos/${MIRROR_REPO}/releases/tags/${encodeURIComponent(tag)}`);
    } catch (e) {
      mirrorHasRelease = false;
    }

    if (mirrorHasRelease) {
      res.status(200).json({ ok: true, tag, action: "noop", reason: "mirror_release_exists" });
      return;
    }

    // 3) Dispatch the workflow to build/publish the release
    const dispatchUrl = `https://api.github.com/repos/${MIRROR_REPO}/actions/workflows/${WORKFLOW_FILE}/dispatches`;
    const d = await fetch(dispatchUrl, {
      method: "POST",
      headers: { ...ghHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ ref: "main" }),
    });
    if (!d.ok) {
      const body = await d.text().catch(() => "");
      throw new Error(`${dispatchUrl} -> ${d.status} ${body.slice(0, 200)}`);
    }

    res.status(200).json({ ok: true, tag, action: "dispatched", workflow: WORKFLOW_FILE });
  } catch (err) {
    res.status(500).json({ ok: false, error: String(err && err.message ? err.message : err) });
  }
}

