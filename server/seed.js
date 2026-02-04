const { save, uuid } = require("./db");

function makeExpression(questionCode, datapointCodes) {
    return {
        and: [
            {
                or: [
                    {
                        question: questionCode,
                        datapoints: datapointCodes
                    }
                ]
            }
        ]
    };
}

const sampleBase = {
    id: "base-1",
    name: "All respondents",
    full_name: "All respondents",
    subtitle: "Total base",
    expression: {}
};

const defaultMetadata = {
    activeMetrics: ["size", "sample", "column_percentage", "row_percentage", "index"],
    metricsTransposition: "row_metrics",
    minimumSampleSize: { cells: 30, rows: 30, columns: 30 },
    frozenCells: { rows: 0, columns: 0 },
    headerSize: { rowWidth: 263, columnHeight: 149 }
};

const folderId = uuid();
const now = new Date().toISOString();

const db = {
    projects: [
        {
            uuid: uuid(),
            user_id: 12345,
            name: "Media Consumption Analysis",
            folder_id: folderId,
            data: {
                rows: [
                    {
                        id: "audience-1",
                        name: "Males 25-34",
                        full_name: "Males aged 25-34",
                        subtitle: "Core demographic",
                        expression: makeExpression("q1", ["1", "2"])
                    },
                    {
                        id: "audience-2",
                        name: "Females 18-24",
                        full_name: "Females aged 18-24",
                        subtitle: "Youth demographic",
                        expression: makeExpression("q1", ["3", "4"])
                    }
                ],
                columns: [
                    {
                        id: "col-1",
                        name: "Social Media Users",
                        full_name: "Social Media Users",
                        subtitle: "Platform usage",
                        expression: makeExpression("q4", ["1", "2", "3"])
                    }
                ],
                country_codes: ["gb", "us"],
                wave_codes: ["q1_2024"],
                bases: [sampleBase],
                metadata: defaultMetadata
            },
            shared: [],
            sharing_note: "",
            sharing_type: null,
            copied_from: null,
            created_at: now,
            updated_at: now
        },
        {
            uuid: uuid(),
            user_id: 12345,
            name: "Brand Awareness Study",
            folder_id: folderId,
            data: {
                rows: [
                    {
                        id: "audience-1",
                        name: "Males 25-34",
                        full_name: "Males aged 25-34",
                        subtitle: "Core demographic",
                        expression: makeExpression("q1", ["1", "2"])
                    }
                ],
                columns: [
                    {
                        id: "col-2",
                        name: "Brand Awareness",
                        full_name: "Brand Awareness",
                        subtitle: "Aided awareness",
                        expression: makeExpression("q6", ["1", "2"])
                    }
                ],
                country_codes: ["gb"],
                wave_codes: ["q1_2024"],
                bases: [sampleBase],
                metadata: defaultMetadata
            },
            shared: [],
            sharing_note: "",
            sharing_type: null,
            copied_from: null,
            created_at: now,
            updated_at: now
        },
        {
            uuid: uuid(),
            user_id: 12345,
            name: "Quick Demographics Table",
            folder_id: null,
            data: {
                rows: [
                    {
                        id: "audience-1",
                        name: "Males 25-34",
                        full_name: "Males aged 25-34",
                        subtitle: "Core demographic",
                        expression: makeExpression("q1", ["1", "2"])
                    },
                    {
                        id: "audience-2",
                        name: "Females 18-24",
                        full_name: "Females aged 18-24",
                        subtitle: "Youth demographic",
                        expression: makeExpression("q2", ["1"])
                    }
                ],
                columns: [
                    {
                        id: "col-3",
                        name: "Online Shoppers",
                        full_name: "Online Shoppers",
                        subtitle: "E-commerce",
                        expression: makeExpression("q5", ["1", "2"])
                    },
                    {
                        id: "col-4",
                        name: "Streamers",
                        full_name: "Video Streamers",
                        subtitle: "Streaming services",
                        expression: makeExpression("q5", ["3", "4"])
                    }
                ],
                country_codes: ["us"],
                wave_codes: ["q1_2024"],
                bases: [sampleBase],
                metadata: defaultMetadata
            },
            shared: [],
            sharing_note: "",
            sharing_type: null,
            copied_from: null,
            created_at: now,
            updated_at: now
        }
    ],
    folders: [{ id: folderId, user_id: 12345, name: "Demo Projects" }],
    userSettings: {
        12345: {
            can_show_shared_project_warning: true,
            xb2_list_ftue_seen: true,
            do_not_show_again: [],
            show_detail_table_in_debug_mode: false,
            pin_debug_options: false
        }
    }
};

save(db);
console.log("Seed data written to data.json");
