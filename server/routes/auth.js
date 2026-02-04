const express = require("express");
const router = express.Router();

const mockUser = {
    id: 12345,
    email: "dev@example.com",
    first_name: "Dev",
    last_name: "User",
    organisation_id: 1,
    organisation_name: "Dev Org",
    country_name: null,
    city_name: null,
    job_title: null,
    plan_handle: "professional",
    customer_features: [
        "crosstabs_locked",
        "xb_20_visible_in_pronext",
        "xb_folders",
        "xb_sorting",
        "debug_buttons"
    ],
    industry: null,
    saw_onboarding: true,
    last_platform_used: "platform2",
    access_start: "2024-01-01T00:00:00.000Z"
};

// GET /api/current_user
router.get("/api/current_user", (req, res) => {
    res.json(mockUser);
});

// GET /v1/organisations/users/:id/organisation
router.get("/v1/organisations/users/:id/organisation", (req, res) => {
    res.json({
        organisation: {
            id: 1,
            name: "Dev Org"
        }
    });
});

// POST /v1/users-next/refresh_tokens
router.post("/v1/users-next/refresh_tokens", (req, res) => {
    res.json({
        access_token: "mock-token",
        refresh_token: "mock-refresh"
    });
});

// PUT /v1/users-next/users/:id/last_platform_used
router.put("/v1/users-next/users/:id/last_platform_used", (req, res) => {
    res.json({ ok: true });
});

module.exports = router;
