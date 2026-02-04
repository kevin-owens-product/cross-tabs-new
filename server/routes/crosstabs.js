const express = require("express");
const router = express.Router();
const { load, save, uuid } = require("../db");

function formatProjectForList(p) {
    return {
        uuid: p.uuid,
        name: p.name,
        folder_id: p.folder_id || "",
        shared: p.shared || [],
        shared_by: { user_id: p.user_id, email: "dev@example.com" },
        sharing_note: p.sharing_note || "",
        sharing_type: p.sharing_type || null,
        copied_from: p.copied_from || "",
        created_at: p.created_at,
        updated_at: p.updated_at,
        user_id: p.user_id
    };
}

function formatProjectFull(p) {
    const data = p.data || {};
    return {
        uuid: p.uuid,
        name: p.name,
        folder_id: p.folder_id || "",
        shared: p.shared || [],
        shared_by: { user_id: p.user_id, email: "dev@example.com" },
        sharing_note: p.sharing_note || "",
        sharing_type: p.sharing_type || null,
        copied_from: p.copied_from || "",
        created_at: p.created_at,
        updated_at: p.updated_at,
        user_id: p.user_id,
        rows: data.rows || [],
        columns: data.columns || [],
        country_codes: data.country_codes || [],
        wave_codes: data.wave_codes || [],
        bases: data.bases || [],
        metadata: data.metadata || null
    };
}

// GET / — List all projects
router.get("/", (req, res) => {
    const db = load();
    const sorted = db.projects
        .slice()
        .sort((a, b) => new Date(b.updated_at) - new Date(a.updated_at));
    res.json({ projects: sorted.map(formatProjectForList) });
});

// GET /:id — Fetch single project
router.get("/:id", (req, res) => {
    const db = load();
    const project = db.projects.find((p) => p.uuid === req.params.id);
    if (!project) return res.status(404).json({ error: "Project not found" });
    res.json(formatProjectFull(project));
});

// POST / — Create project
router.post("/", (req, res) => {
    const db = load();
    const { name, folder_id, rows, columns, country_codes, wave_codes, bases, metadata } =
        req.body;
    const now = new Date().toISOString();
    const project = {
        uuid: uuid(),
        user_id: 12345,
        name: name || "Untitled",
        folder_id: folder_id || null,
        data: {
            rows: rows || [],
            columns: columns || [],
            country_codes: country_codes || [],
            wave_codes: wave_codes || [],
            bases: bases || [],
            metadata: metadata || null
        },
        shared: [],
        sharing_note: "",
        sharing_type: null,
        copied_from: null,
        created_at: now,
        updated_at: now
    };
    db.projects.push(project);
    save(db);
    res.status(201).json(formatProjectFull(project));
});

// PUT /:id — Full update
router.put("/:id", (req, res) => {
    const db = load();
    const idx = db.projects.findIndex((p) => p.uuid === req.params.id);
    if (idx === -1) return res.status(404).json({ error: "Project not found" });

    const { name, folder_id, rows, columns, country_codes, wave_codes, bases, metadata } =
        req.body;
    db.projects[idx].name = name;
    db.projects[idx].folder_id = folder_id || null;
    db.projects[idx].data = {
        rows: rows || [],
        columns: columns || [],
        country_codes: country_codes || [],
        wave_codes: wave_codes || [],
        bases: bases || [],
        metadata: metadata || null
    };
    db.projects[idx].updated_at = new Date().toISOString();
    save(db);
    res.json(formatProjectFull(db.projects[idx]));
});

// PATCH /:id — Partial update
router.patch("/:id", (req, res) => {
    const db = load();
    const idx = db.projects.findIndex((p) => p.uuid === req.params.id);
    if (idx === -1) return res.status(404).json({ error: "Project not found" });

    const p = db.projects[idx];
    const updates = req.body;

    if (updates.name !== undefined) p.name = updates.name;
    if (updates.folder_id !== undefined) p.folder_id = updates.folder_id;

    if (!p.data) p.data = {};
    if (updates.rows !== undefined) p.data.rows = updates.rows;
    if (updates.columns !== undefined) p.data.columns = updates.columns;
    if (updates.country_codes !== undefined) p.data.country_codes = updates.country_codes;
    if (updates.wave_codes !== undefined) p.data.wave_codes = updates.wave_codes;
    if (updates.bases !== undefined) p.data.bases = updates.bases;
    if (updates.metadata !== undefined) p.data.metadata = updates.metadata;

    p.updated_at = new Date().toISOString();
    save(db);
    res.json(formatProjectFull(p));
});

// DELETE /:id — Delete project
router.delete("/:id", (req, res) => {
    const db = load();
    const idx = db.projects.findIndex((p) => p.uuid === req.params.id);
    if (idx === -1) return res.status(404).json({ error: "Project not found" });

    const [removed] = db.projects.splice(idx, 1);
    save(db);
    res.json({ deleted: true, uuid: removed.uuid });
});

module.exports = router;
