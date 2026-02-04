const express = require("express");
const router = express.Router();
const { load, save } = require("../db");

const defaultSettings = {
    can_show_shared_project_warning: true,
    xb2_list_ftue_seen: true,
    do_not_show_again: [],
    show_detail_table_in_debug_mode: false,
    pin_debug_options: false
};

// GET / — Fetch user settings
router.get("/", (req, res) => {
    const db = load();
    const settings = db.userSettings["12345"] || defaultSettings;
    res.json({ data: settings });
});

// POST / — Update user settings
router.post("/", (req, res) => {
    const db = load();
    db.userSettings["12345"] = req.body;
    save(db);
    res.json({ data: req.body });
});

module.exports = router;
