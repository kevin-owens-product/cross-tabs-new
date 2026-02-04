import * as Utils from "./utils";

// ---------------------------------------------------------------------------
// Attribute Browser – mock implementation
// ---------------------------------------------------------------------------
// Reads x-env-values to discover API host, fetches /v2/attributes and
// /v2/questions/:code, renders a category → question → datapoint tree,
// and dispatches the same custom events the real component does.
// ---------------------------------------------------------------------------

class MockAttributeBrowser extends HTMLElement {
    private shadow: ShadowRoot;
    private apiHost = "";
    private token = "";
    private appName = "CrosstabBuilder";

    constructor() {
        super();
        this.shadow = this.attachShadow({ mode: "open" });
    }

    connectedCallback() {
        this.parseConfig();
        this.render();
        this.fetchAttributes();
    }

    private parseConfig() {
        try {
            const raw = this.getAttribute("x-env-values");
            if (raw) {
                const cfg = JSON.parse(raw);
                this.appName = cfg.appName || this.appName;
                this.apiHost = cfg.api?.DEFAULT_HOST || cfg.api?.SERVICE_LAYER_HOST || "";
                this.token = cfg.user?.token || "";
            }
        } catch {
            /* ignore parse errors */
        }
    }

    private emit(eventSuffix: string, detail: any) {
        this.dispatchEvent(
            new CustomEvent(`${this.appName}-${eventSuffix}`, {
                bubbles: true,
                composed: true,
                detail
            })
        );
    }

    private async apiFetch(path: string) {
        const res = await fetch(`${this.apiHost}${path}`, {
            headers: {
                Authorization: `Bearer ${this.token}`,
                "Content-Type": "application/json"
            }
        });
        return res.json();
    }

    private render() {
        this.shadow.innerHTML = `
            <style>
                :host { display: block; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size: 13px; color: #333; }
                .ab-root { border: 1px solid #ddd; border-radius: 6px; background: #fff; max-height: 480px; overflow-y: auto; }
                .ab-header { padding: 10px 14px; font-weight: 600; font-size: 14px; border-bottom: 1px solid #eee; background: #f8f9fa; border-radius: 6px 6px 0 0; }
                .ab-loading { padding: 20px; text-align: center; color: #888; }
                .ab-category { border-bottom: 1px solid #f0f0f0; }
                .ab-cat-title { padding: 8px 14px; font-weight: 600; cursor: pointer; background: #fafafa; user-select: none; }
                .ab-cat-title:hover { background: #f0f0f0; }
                .ab-questions { display: none; }
                .ab-questions.open { display: block; }
                .ab-question { padding: 6px 14px 6px 28px; cursor: pointer; display: flex; align-items: center; gap: 6px; }
                .ab-question:hover { background: #e8f0fe; }
                .ab-dp-list { padding-left: 42px; }
                .ab-dp { padding: 4px 14px; cursor: pointer; display: flex; align-items: center; gap: 6px; }
                .ab-dp:hover { background: #e8f0fe; }
                .ab-dp .cb, .ab-question .cb { width: 14px; height: 14px; border: 1px solid #999; border-radius: 3px; flex-shrink: 0; }
                .ab-dp .cb.checked, .ab-question .cb.checked { background: #1a73e8; border-color: #1a73e8; }
            </style>
            <div class="ab-root">
                <div class="ab-header">Attribute Browser</div>
                <div class="ab-loading" id="ab-content">Loading attributes…</div>
            </div>
        `;
    }

    private async fetchAttributes() {
        try {
            const data = await this.apiFetch("/v2/attributes");
            const attrs: Array<{
                code: string;
                name: string;
                namespace_code: string;
                questions: Array<{ code: string; name: string; namespace_code: string }>;
            }> = data.attributes || [];
            this.renderCategories(attrs);
        } catch (e) {
            const el = this.shadow.getElementById("ab-content");
            if (el) el.textContent = "Failed to load attributes.";
        }
    }

    private renderCategories(categories: Array<any>) {
        const container = this.shadow.getElementById("ab-content");
        if (!container) return;
        container.className = "";
        container.innerHTML = "";

        for (const cat of categories) {
            const catEl = document.createElement("div");
            catEl.className = "ab-category";

            const title = document.createElement("div");
            title.className = "ab-cat-title";
            title.textContent = `▶ ${cat.name}`;

            const questionsEl = document.createElement("div");
            questionsEl.className = "ab-questions";

            title.addEventListener("click", () => {
                const isOpen = questionsEl.classList.toggle("open");
                title.textContent = `${isOpen ? "▼" : "▶"} ${cat.name}`;
            });

            for (const q of cat.questions) {
                const qRow = document.createElement("div");
                qRow.className = "ab-question";
                qRow.innerHTML = `<span class="cb"></span> ${q.name}`;

                const dpContainer = document.createElement("div");
                dpContainer.className = "ab-dp-list";
                dpContainer.style.display = "none";
                let loaded = false;

                qRow.addEventListener("click", async () => {
                    if (!loaded) {
                        loaded = true;
                        try {
                            const qData = await this.apiFetch(`/v2/questions/${q.code}`);
                            const question = qData.question;
                            if (question && question.datapoints) {
                                for (const dp of question.datapoints) {
                                    const dpRow = document.createElement("div");
                                    dpRow.className = "ab-dp";
                                    dpRow.innerHTML = `<span class="cb"></span> ${dp.name}`;
                                    dpRow.addEventListener("click", (e) => {
                                        e.stopPropagation();
                                        const cb = dpRow.querySelector(".cb");
                                        cb?.classList.toggle("checked");
                                        this.toggleAttribute(
                                            q.namespace_code ||
                                                cat.namespace_code ||
                                                "core",
                                            q.code,
                                            dp.code,
                                            q.name,
                                            dp.name,
                                            question.description || q.name,
                                            dp.order ?? 1
                                        );
                                    });
                                    dpContainer.appendChild(dpRow);
                                }
                            }
                        } catch {
                            /* ignore */
                        }
                    }
                    dpContainer.style.display =
                        dpContainer.style.display === "none" ? "block" : "none";
                });

                questionsEl.appendChild(qRow);
                questionsEl.appendChild(dpContainer);
            }

            catEl.appendChild(title);
            catEl.appendChild(questionsEl);
            container.appendChild(catEl);
        }
    }

    private toggleAttribute(
        namespace: string,
        questionCode: string,
        datapointCode: string,
        questionLabel: string,
        datapointLabel: string,
        questionDescription: string,
        order: number
    ) {
        const attribute = {
            compatibleAttribute: {
                namespace_code: namespace,
                question_code: questionCode,
                datapoint_code: datapointCode,
                question_label: questionLabel,
                datapoint_label: datapointLabel,
                suffix_label: "",
                question_description: questionDescription,
                order: order
            }
        };
        this.emit("attributeBrowserLeftAttributesToggled", { attributes: [attribute] });
    }
}

// ---------------------------------------------------------------------------
// Audience Browser – mock implementation
// ---------------------------------------------------------------------------

class MockAudienceBrowser extends HTMLElement {
    private shadow: ShadowRoot;
    private apiHost = "";
    private token = "";
    private appName = "CrosstabBuilder";
    private stagedIds: Set<string> = new Set();

    constructor() {
        super();
        this.shadow = this.attachShadow({ mode: "open" });
    }

    connectedCallback() {
        this.parseConfig();
        this.parseStagedAudiences();
        this.render();
        this.fetchAudiences();
    }

    private parseConfig() {
        try {
            const raw = this.getAttribute("x-env-values");
            if (raw) {
                const cfg = JSON.parse(raw);
                this.appName = cfg.appName || this.appName;
                this.apiHost = cfg.api?.DEFAULT_HOST || cfg.api?.SERVICE_LAYER_HOST || "";
                this.token = cfg.user?.token || "";
            }
        } catch {
            /* ignore */
        }
    }

    private parseStagedAudiences() {
        try {
            const raw = this.getAttribute("staged-audiences");
            if (raw) {
                const ids: string[] = JSON.parse(raw);
                ids.forEach((id) => this.stagedIds.add(id));
            }
        } catch {
            /* ignore */
        }
    }

    private emit(eventSuffix: string, detail: any) {
        this.dispatchEvent(
            new CustomEvent(`${this.appName}-${eventSuffix}`, {
                bubbles: true,
                composed: true,
                detail
            })
        );
    }

    private async apiFetch(path: string) {
        const res = await fetch(`${this.apiHost}${path}`, {
            headers: {
                Authorization: `Bearer ${this.token}`,
                "Content-Type": "application/json"
            }
        });
        return res.json();
    }

    private render() {
        this.shadow.innerHTML = `
            <style>
                :host { display: block; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size: 13px; color: #333; }
                .aub-root { border: 1px solid #ddd; border-radius: 6px; background: #fff; max-height: 480px; overflow-y: auto; }
                .aub-header { padding: 10px 14px; font-weight: 600; font-size: 14px; border-bottom: 1px solid #eee; background: #f8f9fa; border-radius: 6px 6px 0 0; display: flex; justify-content: space-between; align-items: center; }
                .aub-loading { padding: 20px; text-align: center; color: #888; }
                .aub-section { border-bottom: 1px solid #f0f0f0; }
                .aub-section-title { padding: 8px 14px; font-weight: 600; font-size: 12px; text-transform: uppercase; color: #666; background: #fafafa; letter-spacing: 0.5px; }
                .aub-item { padding: 8px 14px; cursor: pointer; display: flex; align-items: center; gap: 8px; border-bottom: 1px solid #f5f5f5; }
                .aub-item:hover { background: #e8f0fe; }
                .aub-item .cb { width: 14px; height: 14px; border: 1px solid #999; border-radius: 3px; flex-shrink: 0; }
                .aub-item .cb.checked { background: #1a73e8; border-color: #1a73e8; }
                .aub-item-name { flex: 1; }
                .aub-item-badge { font-size: 11px; padding: 1px 6px; border-radius: 10px; background: #e0e0e0; color: #555; }
                .aub-item-badge.shared { background: #e3f2fd; color: #1565c0; }
                .aub-btn { padding: 5px 12px; background: #1a73e8; color: #fff; border: none; border-radius: 4px; cursor: pointer; font-size: 12px; }
                .aub-btn:hover { background: #1557b0; }
            </style>
            <div class="aub-root">
                <div class="aub-header">
                    <span>Audience Browser</span>
                    <button class="aub-btn" id="aub-create">+ Create</button>
                </div>
                <div class="aub-loading" id="aub-content">Loading audiences…</div>
            </div>
        `;
        this.shadow.getElementById("aub-create")?.addEventListener("click", () => {
            this.emit("audienceBrowserLeftAudienceBuilderCreateClicked", {});
        });
    }

    private async fetchAudiences() {
        try {
            const data = await this.apiFetch("/v2/audiences/saved");
            const audiences: Array<any> = data.data || [];
            this.renderAudiences(audiences);
        } catch (e) {
            const el = this.shadow.getElementById("aub-content");
            if (el) el.textContent = "Failed to load audiences.";
        }
    }

    private renderAudiences(audiences: Array<any>) {
        const container = this.shadow.getElementById("aub-content");
        if (!container) return;
        container.className = "";
        container.innerHTML = "";

        if (audiences.length === 0) {
            container.innerHTML = `<div style="padding: 20px; text-align: center; color: #888; font-style: italic;">No saved audiences yet.</div>`;
            return;
        }

        const myAudiences = audiences.filter((a) => !a.shared);
        const sharedAudiences = audiences.filter((a) => a.shared);

        if (myAudiences.length > 0) {
            const section = document.createElement("div");
            section.className = "aub-section";
            section.innerHTML = `<div class="aub-section-title">My Audiences</div>`;
            for (const aud of myAudiences) {
                section.appendChild(this.createAudienceRow(aud));
            }
            container.appendChild(section);
        }

        if (sharedAudiences.length > 0) {
            const section = document.createElement("div");
            section.className = "aub-section";
            section.innerHTML = `<div class="aub-section-title">Shared Audiences</div>`;
            for (const aud of sharedAudiences) {
                section.appendChild(this.createAudienceRow(aud));
            }
            container.appendChild(section);
        }
    }

    private createAudienceRow(audience: any): HTMLElement {
        const row = document.createElement("div");
        row.className = "aub-item";

        const isStaged = this.stagedIds.has(audience.id);
        const badge = audience.shared
            ? `<span class="aub-item-badge shared">shared</span>`
            : "";

        row.innerHTML = `<span class="cb${isStaged ? " checked" : ""}"></span><span class="aub-item-name">${audience.name}</span>${badge}`;

        row.addEventListener("click", () => {
            const cb = row.querySelector(".cb");
            cb?.classList.toggle("checked");
            this.emit("audienceBrowserLeftToggledEvent", { payload: audience });
        });

        return row;
    }
}

// ---------------------------------------------------------------------------
// Audience Expression Viewer – lightweight stub
// ---------------------------------------------------------------------------

class MockAudienceExpressionViewer extends HTMLElement {
    constructor() {
        super();
    }
    connectedCallback() {
        const shadow = this.attachShadow({ mode: "open" });
        shadow.innerHTML = `
            <style>
                :host { display: block; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size: 12px; color: #666; }
                .expr { padding: 6px 10px; background: #f5f5f5; border-radius: 4px; border: 1px solid #e0e0e0; }
            </style>
            <div class="expr">Audience expression</div>
        `;
    }
}

// ---------------------------------------------------------------------------
// Splash Screen – just renders nothing (app is already loaded)
// ---------------------------------------------------------------------------

class MockSplashScreen extends HTMLElement {
    constructor() {
        super();
    }
    connectedCallback() {
        // no-op: the app handles its own loading state
    }
}

// ---------------------------------------------------------------------------
// Register all components
// ---------------------------------------------------------------------------

Utils.register("x-et-attribute-browser", MockAttributeBrowser);
Utils.register("x-et-audience-browser", MockAudienceBrowser);
Utils.register("x-et-audience-expression-viewer", MockAudienceExpressionViewer);
Utils.register("x-et-splash-screen", MockSplashScreen);
