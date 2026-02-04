const express = require("express");
const router = express.Router();

// POST /identify
router.post("/identify", (req, res) => {
    res.json({ ok: true });
});

// POST /track
router.post("/track", (req, res) => {
    res.json({ ok: true });
});

// POST /batch
router.post("/batch", (req, res) => {
    res.json({ ok: true });
});

module.exports = router;
