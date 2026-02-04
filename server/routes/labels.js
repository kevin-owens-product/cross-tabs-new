const express = require("express");
const { v4: uuidv4 } = require("uuid");
const router = express.Router();

// Static fixture data for locations
const locations = [
    { code: "gb", name: "United Kingdom", region: { area: "euro" }, accessible: true },
    { code: "us", name: "United States", region: { area: "americas" }, accessible: true },
    { code: "de", name: "Germany", region: { area: "euro" }, accessible: true },
    { code: "fr", name: "France", region: { area: "euro" }, accessible: true },
    { code: "jp", name: "Japan", region: { area: "apac" }, accessible: true },
    { code: "br", name: "Brazil", region: { area: "americas" }, accessible: true },
    { code: "au", name: "Australia", region: { area: "apac" }, accessible: true },
    { code: "in", name: "India", region: { area: "apac" }, accessible: true },
    { code: "ca", name: "Canada", region: { area: "americas" }, accessible: true },
    { code: "mx", name: "Mexico", region: { area: "americas" }, accessible: true },
    { code: "es", name: "Spain", region: { area: "euro" }, accessible: true },
    { code: "it", name: "Italy", region: { area: "euro" }, accessible: true },
    { code: "za", name: "South Africa", region: { area: "mea" }, accessible: true },
    {
        code: "ae",
        name: "United Arab Emirates",
        region: { area: "mea" },
        accessible: true
    }
];

// Static fixture data for waves
const waves = [
    {
        code: "q1_2024",
        name: "Q1 2024",
        accessible: true,
        kind: "quarter",
        date_start: "2024-01-01",
        date_end: "2024-03-31"
    },
    {
        code: "q2_2024",
        name: "Q2 2024",
        accessible: true,
        kind: "quarter",
        date_start: "2024-04-01",
        date_end: "2024-06-30"
    },
    {
        code: "q3_2024",
        name: "Q3 2024",
        accessible: true,
        kind: "quarter",
        date_start: "2024-07-01",
        date_end: "2024-09-30"
    },
    {
        code: "q4_2024",
        name: "Q4 2024",
        accessible: true,
        kind: "quarter",
        date_start: "2024-10-01",
        date_end: "2024-12-31"
    },
    {
        code: "q1_2023",
        name: "Q1 2023",
        accessible: true,
        kind: "quarter",
        date_start: "2023-01-01",
        date_end: "2023-03-31"
    },
    {
        code: "q2_2023",
        name: "Q2 2023",
        accessible: true,
        kind: "quarter",
        date_start: "2023-04-01",
        date_end: "2023-06-30"
    }
];

// Static fixture for questions
function generateQuestion(code, name, datapointCount) {
    const datapoints = [];
    for (let i = 1; i <= datapointCount; i++) {
        datapoints.push({
            code: String(i),
            name: `${name} - Option ${i}`,
            accessible: true,
            midpoint: null,
            order: i
        });
    }
    return {
        code: code,
        namespace_code: "core",
        name: name,
        description: `${name} question`,
        categories: [{ id: "cat-1" }],
        suffixes: [{ code: "default", name: "Default", midpoint: null }],
        message: null,
        accessible: true,
        notice: null,
        unit: null,
        flags: [],
        warning: null,
        knowledge_base: null,
        datapoints: datapoints
    };
}

// Static datasets
const datasets = [
    {
        code: "core",
        name: "Core",
        description: "Core dataset",
        accessible: true
    }
];

// GET /v2/attributes — Attributes listing
router.get("/v2/attributes", (req, res) => {
    res.json({
        attributes: [
            {
                code: "demographics",
                name: "Demographics",
                namespace_code: "core",
                questions: [
                    { code: "q1", name: "Age", namespace_code: "core" },
                    { code: "q2", name: "Gender", namespace_code: "core" },
                    { code: "q3", name: "Income", namespace_code: "core" }
                ]
            },
            {
                code: "media",
                name: "Media Consumption",
                namespace_code: "core",
                questions: [
                    { code: "q4", name: "Social Media Usage", namespace_code: "core" },
                    { code: "q5", name: "Streaming Services", namespace_code: "core" }
                ]
            },
            {
                code: "attitudes",
                name: "Attitudes",
                namespace_code: "core",
                questions: [
                    { code: "q6", name: "Brand Perception", namespace_code: "core" },
                    { code: "q7", name: "Purchase Intent", namespace_code: "core" }
                ]
            }
        ]
    });
});

// GET /v2/questions/:code — Single question detail
router.get("/v2/questions/:code", (req, res) => {
    const questionMap = {
        q1: generateQuestion("q1", "Age", 7),
        q2: generateQuestion("q2", "Gender", 3),
        q3: generateQuestion("q3", "Income", 8),
        q4: generateQuestion("q4", "Social Media Usage", 6),
        q5: generateQuestion("q5", "Streaming Services", 5),
        q6: generateQuestion("q6", "Brand Perception", 5),
        q7: generateQuestion("q7", "Purchase Intent", 4)
    };

    const question = questionMap[req.params.code];
    if (question) {
        res.json({ question });
    } else {
        // Generate a generic question for any unknown code
        res.json({
            question: generateQuestion(req.params.code, `Question ${req.params.code}`, 5)
        });
    }
});

// POST /v2/locations/filter — Get locations
router.post("/v2/locations/filter", (req, res) => {
    res.json({ locations });
});

// POST /v2/waves/filter — Get waves
router.post("/v2/waves/filter", (req, res) => {
    res.json({ waves });
});

// GET /v1/datasets — List datasets
router.get("/v1/datasets", (req, res) => {
    res.json({ datasets });
});

// GET /v1/collections — List collections
router.get("/v1/collections", (req, res) => {
    res.json({ collections: [] });
});

// Any audience-builder endpoints
router.get("/v1/audience-builder", (req, res) => {
    res.json({ audiences: [] });
});

router.post("/v1/audience-builder", (req, res) => {
    res.json({ audiences: [] });
});

// Static fixture data for saved audiences
const savedAudiences = [
    {
        id: "a1b2c3d4-0001-4000-8000-000000000001",
        name: "Millennials (25-34)",
        expression: { question: "q1", datapoints: ["q1_3", "q1_4"] },
        shared: false,
        flags: ["authored", "isP2"],
        folder_id: null,
        created_at: "2024-11-15T09:30:00Z",
        updated_at: "2024-12-20T14:15:00Z"
    },
    {
        id: "a1b2c3d4-0002-4000-8000-000000000002",
        name: "Gen Z (18-24)",
        expression: { question: "q1", datapoints: ["q1_1", "q1_2"] },
        shared: false,
        flags: ["authored", "isP2"],
        folder_id: null,
        created_at: "2024-10-05T11:00:00Z",
        updated_at: "2024-12-18T08:45:00Z"
    },
    {
        id: "a1b2c3d4-0003-4000-8000-000000000003",
        name: "High Income Streamers",
        expression: {
            and: [
                { question: "q3", datapoints: ["q3_6", "q3_7", "q3_8"] },
                { question: "q5", datapoints: ["q5_1", "q5_2", "q5_3"] }
            ]
        },
        shared: true,
        flags: ["curated"],
        folder_id: null,
        created_at: "2024-09-01T16:00:00Z",
        updated_at: "2024-11-30T10:20:00Z"
    },
    {
        id: "a1b2c3d4-0004-4000-8000-000000000004",
        name: "Brand Enthusiasts",
        expression: { question: "q6", datapoints: ["q6_4", "q6_5"] },
        shared: true,
        flags: ["curated"],
        folder_id: null,
        created_at: "2024-08-12T13:30:00Z",
        updated_at: "2024-10-25T17:00:00Z"
    },
    {
        id: "a1b2c3d4-0005-4000-8000-000000000005",
        name: "Social Media Power Users",
        expression: { question: "q4", datapoints: ["q4_1", "q4_2", "q4_3", "q4_4"] },
        shared: false,
        flags: ["authored", "isP2"],
        folder_id: null,
        created_at: "2024-12-01T10:00:00Z",
        updated_at: "2025-01-10T09:00:00Z"
    },
    {
        id: "a1b2c3d4-0006-4000-8000-000000000006",
        name: "Purchase Intenders",
        expression: { question: "q7", datapoints: ["q7_3", "q7_4"] },
        shared: false,
        flags: ["authored", "isP2"],
        folder_id: null,
        created_at: "2025-01-05T14:00:00Z",
        updated_at: "2025-01-20T11:30:00Z"
    }
];

// v2 audiences
router.get("/v2/audiences", (req, res) => {
    res.json({ audiences: savedAudiences });
});

router.post("/v2/audiences", (req, res) => {
    res.json({ audiences: savedAudiences });
});

// GET /v2/audiences/saved — List saved audiences
// Also mounted at /platform/v2/audiences/saved (web component uses the platform prefix)
router.get("/v2/audiences/saved", (req, res) => {
    res.json({ data: savedAudiences });
});
router.get("/platform/v2/audiences/saved", (req, res) => {
    res.json({ data: savedAudiences });
});

// GET /platform/datasets — Datasets via service layer
// Decoder expects a raw array (not wrapped in { datasets: [...] })
router.get("/platform/datasets", (req, res) => {
    res.json([
        {
            code: "core",
            name: "Core",
            description: "Core survey dataset",
            base_namespace_code: "core",
            categories: [
                { id: "demographics", name: "Demographics", order: 1.0 },
                { id: "media", name: "Media Consumption", order: 2.0 },
                { id: "attitudes", name: "Attitudes", order: 3.0 }
            ],
            depth: 0
        }
    ]);
});

// GET /platform/dataset-folders — Dataset folders
// Decoder expects a raw array of folder objects
router.get("/platform/dataset-folders", (req, res) => {
    res.json([]);
});

// GET /v2/audiences/saved/folders — Saved audience folders
// Decoder expects { data: [...] } with full folder objects
router.get("/v2/audiences/saved/folders", (req, res) => {
    res.json({ data: [] });
});

// GET /v1/surveys/lineage/by_namespace/:namespace — Survey lineage
// Decoder expects { ancestors: {key: null, ...}, descendants: {key: null, ...} }
router.get("/v1/surveys/lineage/by_namespace/:namespace", (req, res) => {
    res.json({ ancestors: {}, descendants: {} });
});

// POST /v2/users/suggest — User suggestion for sharing dialog
router.post("/v2/users/suggest", (req, res) => {
    const hint = req.query.hint || req.body.hint || "";
    if (!hint) {
        return res.json({ users: [] });
    }
    res.json({
        users: [
            {
                id: 99999,
                email: hint.includes("@") ? hint : `${hint}@example.com`,
                first_name: "Mock",
                last_name: "User"
            }
        ]
    });
});

// POST /v2/audiences/saved — Create a saved audience
router.post("/v2/audiences/saved", (req, res) => {
    const { name, flags, expression, datasets } = req.body;
    const now = new Date().toISOString();
    res.status(201).json({
        id: uuidv4(),
        name: name || "New Audience",
        expression: expression || {},
        shared: false,
        flags: flags || {},
        folder_id: null,
        created_at: now,
        updated_at: now
    });
});

module.exports = router;
