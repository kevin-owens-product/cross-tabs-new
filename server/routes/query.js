const express = require("express");
const router = express.Router();

// Simple seeded random number generator
function seededRandom(seed) {
    let s = seed;
    return function () {
        s = (s * 1664525 + 1013904223) & 0xffffffff;
        return (s >>> 0) / 0xffffffff;
    };
}

// Hash a string to a number for consistent seeding
function hashString(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash + char) | 0;
    }
    return Math.abs(hash);
}

// Generate mock intersection data for a row/column pair
function generateIntersection(rowId, colId) {
    const seed = hashString(`${rowId}__${colId}`);
    const rng = seededRandom(seed);

    const sample = Math.floor(rng() * 49500) + 500; // 500-50000
    const size = Math.floor(rng() * 9900000) + 100000; // 100k-10M
    const index = Math.floor(rng() * 250) + 50; // 50-300
    const rowPct = Math.floor(rng() * 89) + 1; // 1-90
    const colPct = Math.floor(rng() * 89) + 1; // 1-90
    const rowSample = Math.floor(sample * (rng() * 0.8 + 0.2));
    const colSample = Math.floor(sample * (rng() * 0.8 + 0.2));
    const rowSize = Math.floor(size * (rng() * 0.8 + 0.2));
    const colSize = Math.floor(size * (rng() * 0.8 + 0.2));

    return {
        data: {
            intersect: {
                size: size,
                sample: sample,
                index: index
            },
            audiences: {
                row: {
                    audience: rowId,
                    intersect_percentage: rowPct,
                    sample: rowSample,
                    size: rowSize
                },
                column: {
                    audience: colId,
                    intersect_percentage: colPct,
                    sample: colSample,
                    size: colSize
                }
            }
        },
        meta: {}
    };
}

// POST /intersection — Single cell intersection
router.post("/intersection", (req, res) => {
    const { audiences } = req.body;
    const rowId =
        audiences && audiences.row ? audiences.row.id || "row-default" : "row-default";
    const colId =
        audiences && audiences.column
            ? audiences.column.id || "col-default"
            : "col-default";
    res.json(generateIntersection(rowId, colId));
});

// POST /intersection/export — Export query (same format)
router.post("/intersection/export", (req, res) => {
    const { audiences } = req.body;
    const rowId =
        audiences && audiences.row ? audiences.row.id || "row-default" : "row-default";
    const colId =
        audiences && audiences.column
            ? audiences.column.id || "col-default"
            : "col-default";
    res.json(generateIntersection(rowId, colId));
});

// POST /intersection/heatmap — Heatmap query (same format)
router.post("/intersection/heatmap", (req, res) => {
    const { audiences } = req.body;
    const rowId =
        audiences && audiences.row ? audiences.row.id || "row-default" : "row-default";
    const colId =
        audiences && audiences.column
            ? audiences.column.id || "col-default"
            : "col-default";
    res.json(generateIntersection(rowId, colId));
});

// POST /crosstab — Bulk crosstab query (newline-delimited JSON)
router.post("/crosstab", (req, res) => {
    const { rows, columns } = req.body;
    const rowList = rows || [];
    const colList = columns || [];

    res.setHeader("Content-Type", "application/x-ndjson");

    const lines = [];
    for (let ri = 0; ri < rowList.length; ri++) {
        for (let ci = 0; ci < colList.length; ci++) {
            const rowId = rowList[ri].id || `row-${ri}`;
            const colId = colList[ci].id || `col-${ci}`;
            const intersectionData = generateIntersection(rowId, colId);
            lines.push(
                JSON.stringify({
                    row_index: ri,
                    column_index: ci,
                    intersect: intersectionData.data.intersect,
                    audiences: intersectionData.data.audiences
                })
            );
        }
    }
    res.send(lines.join("\n") + "\n");
});

// POST /crosstab/export — Export (same as crosstab)
router.post("/crosstab/export", (req, res) => {
    const { rows, columns } = req.body;
    const rowList = rows || [];
    const colList = columns || [];

    res.setHeader("Content-Type", "application/x-ndjson");

    const lines = [];
    for (let ri = 0; ri < rowList.length; ri++) {
        for (let ci = 0; ci < colList.length; ci++) {
            const rowId = rowList[ri].id || `row-${ri}`;
            const colId = colList[ci].id || `col-${ci}`;
            const intersectionData = generateIntersection(rowId, colId);
            lines.push(
                JSON.stringify({
                    row_index: ri,
                    column_index: ci,
                    intersect: intersectionData.data.intersect,
                    audiences: intersectionData.data.audiences
                })
            );
        }
    }
    res.send(lines.join("\n") + "\n");
});

// POST /crosstab/heatmap
router.post("/crosstab/heatmap", (req, res) => {
    const { rows, columns } = req.body;
    const rowList = rows || [];
    const colList = columns || [];

    res.setHeader("Content-Type", "application/x-ndjson");

    const lines = [];
    for (let ri = 0; ri < rowList.length; ri++) {
        for (let ci = 0; ci < colList.length; ci++) {
            const rowId = rowList[ri].id || `row-${ri}`;
            const colId = colList[ci].id || `col-${ci}`;
            const intersectionData = generateIntersection(rowId, colId);
            lines.push(
                JSON.stringify({
                    row_index: ri,
                    column_index: ci,
                    intersect: intersectionData.data.intersect,
                    audiences: intersectionData.data.audiences
                })
            );
        }
    }
    res.send(lines.join("\n") + "\n");
});

// POST /average — Average query
router.post("/average", (req, res) => {
    const seed = hashString(JSON.stringify(req.body));
    const rng = seededRandom(seed);
    res.json({ average: Math.round(rng() * 100 * 10) / 10 });
});

module.exports = router;
