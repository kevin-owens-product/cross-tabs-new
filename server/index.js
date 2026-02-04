const express = require("express");
const cors = require("cors");

const authRoutes = require("./routes/auth");
const crosstabsRoutes = require("./routes/crosstabs");
const foldersRoutes = require("./routes/folders");
const sharingRoutes = require("./routes/sharing");
const userSettingsRoutes = require("./routes/userSettings");
const queryRoutes = require("./routes/query");
const analyticsRoutes = require("./routes/analytics");
const labelsRoutes = require("./routes/labels");

const app = express();
const PORT = process.env.PORT || 4000;

app.use(cors());
app.use(express.json({ limit: "10mb" }));

// Request logging
app.use((req, res, next) => {
    console.log(`[${req.method}] ${req.url}`);
    next();
});

// Auth
app.use("/", authRoutes);

// Mount more-specific sub-paths before the general CRUD router
// so that /:id doesn't swallow "folders", "share", "user_settings"

// Folders
app.use("/platform/v1/crosstabs/saved/crosstabs/folders", foldersRoutes);

// Sharing
app.use("/platform/v1/crosstabs/saved/crosstabs/share", sharingRoutes);

// User Settings
app.use("/platform/v1/crosstabs/saved/crosstabs/user_settings", userSettingsRoutes);

// Crosstab CRUD (general — must come after the specific sub-paths)
app.use("/platform/v1/crosstabs/saved/crosstabs", crosstabsRoutes);

// Query / Intersection
app.use("/v2/query", queryRoutes);

// Incompatibilities
app.post("/platform/v1/crosstabs/incompatibilities-bulk", (req, res) => {
    res.json({ cells_response: [] });
});

// Analytics
app.use("/v1/analytics", analyticsRoutes);

// Excel export
app.post("/v3/exports/crosstab.xlsx", (req, res) => {
    res.json({ download_url: "/mock-export.xlsx" });
});

// Labels / Attributes / Questions / Locations / Waves
app.use("/", labelsRoutes);

// Catch-all for unhandled routes
app.use((req, res) => {
    console.log(`[404] ${req.method} ${req.url}`);
    res.status(404).json({ error: "Not found", path: req.url });
});

app.listen(PORT, () => {
    console.log(`Mock API server running on http://localhost:${PORT}`);
});
