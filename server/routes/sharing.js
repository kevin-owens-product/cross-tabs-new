const express = require("express");
const router = express.Router();
const { load, save } = require("../db");

// POST /validate — Validate user email for sharing
router.post("/validate", (req, res) => {
    const { email } = req.body;
    res.json([{ user_id: 99999, email: email || "shared@example.com" }]);
});

// POST /:projectId — Share project
router.post("/:projectId", (req, res) => {
    const db = load();
    const project = db.projects.find((p) => p.uuid === req.params.projectId);
    if (!project) return res.status(404).json({ error: "Project not found" });

    if (req.body.sharing_type !== undefined) project.sharing_type = req.body.sharing_type;
    if (req.body.shared !== undefined) project.shared = req.body.shared;
    if (req.body.sharing_note !== undefined) project.sharing_note = req.body.sharing_note;
    project.updated_at = new Date().toISOString();
    save(db);

    res.json({
        uuid: project.uuid,
        shared: project.shared,
        sharing_type: project.sharing_type,
        sharing_note: project.sharing_note
    });
});

// DELETE /remove/:projectId — Remove sharing
router.delete("/remove/:projectId", (req, res) => {
    const db = load();
    const project = db.projects.find((p) => p.uuid === req.params.projectId);
    if (!project) return res.status(404).json({ error: "Project not found" });

    project.shared = [];
    project.sharing_type = null;
    project.sharing_note = "";
    project.updated_at = new Date().toISOString();
    save(db);
    res.json({ ok: true });
});

module.exports = router;
