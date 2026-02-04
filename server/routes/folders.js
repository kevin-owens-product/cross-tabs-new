const express = require("express");
const router = express.Router();
const { load, save, uuid } = require("../db");

// GET / — List all folders
router.get("/", (req, res) => {
    const db = load();
    const sorted = db.folders.slice().sort((a, b) => a.name.localeCompare(b.name));
    res.json({ data: sorted.map((f) => ({ id: f.id, name: f.name })) });
});

// POST / — Create folder
router.post("/", (req, res) => {
    const db = load();
    const folder = { id: uuid(), user_id: 12345, name: req.body.name || "New Folder" };
    db.folders.push(folder);
    save(db);
    res.status(201).json({ id: folder.id, name: folder.name });
});

// PATCH /:id — Rename folder
router.patch("/:id", (req, res) => {
    const db = load();
    const folder = db.folders.find((f) => f.id === req.params.id);
    if (!folder) return res.status(404).json({ error: "Folder not found" });
    folder.name = req.body.name;
    save(db);
    res.json({ id: folder.id, name: folder.name });
});

// DELETE /:id — Delete empty folder
router.delete("/:id", (req, res) => {
    const db = load();
    db.folders = db.folders.filter((f) => f.id !== req.params.id);
    save(db);
    res.json({ deleted: true });
});

// DELETE /:id/recursive — Delete folder and its projects
router.delete("/:id/recursive", (req, res) => {
    const db = load();
    db.projects = db.projects.filter((p) => p.folder_id !== req.params.id);
    db.folders = db.folders.filter((f) => f.id !== req.params.id);
    save(db);
    res.json({ deleted: true });
});

module.exports = router;
