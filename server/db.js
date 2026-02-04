const fs = require("fs");
const path = require("path");
const { v4: uuidv4 } = require("uuid");

const DB_PATH = path.join(__dirname, "data.json");

const emptyDb = {
    projects: [],
    folders: [],
    userSettings: {}
};

function load() {
    try {
        if (fs.existsSync(DB_PATH)) {
            return JSON.parse(fs.readFileSync(DB_PATH, "utf-8"));
        }
    } catch (err) {
        console.error("Error loading db, starting fresh:", err.message);
    }
    return JSON.parse(JSON.stringify(emptyDb));
}

function save(db) {
    fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2));
}

function uuid() {
    return uuidv4();
}

module.exports = { load, save, uuid, DB_PATH };
