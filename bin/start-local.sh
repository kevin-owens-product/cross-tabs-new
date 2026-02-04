#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_PID=""
WEBPACK_PID=""

cleanup() {
    echo ""
    echo "Shutting down..."
    [ -n "$WEBPACK_PID" ] && kill "$WEBPACK_PID" 2>/dev/null || true
    [ -n "$API_PID" ] && kill "$API_PID" 2>/dev/null || true
    echo "Done."
}
trap cleanup EXIT

# 1. Install server dependencies if needed
if [ ! -d "$ROOT_DIR/server/node_modules" ]; then
    echo "Installing server dependencies..."
    cd "$ROOT_DIR/server" && npm install && cd "$ROOT_DIR"
fi

# 2. Seed if data.json doesn't exist
if [ ! -f "$ROOT_DIR/server/data.json" ]; then
    echo "Seeding mock data..."
    cd "$ROOT_DIR/server" && node seed.js && cd "$ROOT_DIR"
fi

# 3. Start API server in background
echo "Starting API server on port 4000..."
cd "$ROOT_DIR/server" && node index.js &
API_PID=$!
cd "$ROOT_DIR"
sleep 1

# Verify API is up
if curl -s http://localhost:4000/api/current_user >/dev/null 2>&1; then
    echo "API server is running."
else
    echo "WARNING: API server may not have started correctly."
fi

# 4. Start webpack dev server
echo "Starting webpack dev server on port 3000..."
cd "$ROOT_DIR"
TARGET_ENV=development npx webpack serve --config src/crosstab-builder/XB2/webpack.standalone.config.js &
WEBPACK_PID=$!

echo ""
echo "================================================"
echo "  Local dev environment is running!"
echo "  App:  http://localhost:3000"
echo "  API:  http://localhost:4000"
echo "  Data: server/data.json"
echo "================================================"
echo ""

# Wait for either process to exit
wait
