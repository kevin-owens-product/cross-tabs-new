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
                :host {
                    display: block;
                    font-family: Faktum, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    font-size: 13px;
                    color: #191530;
                }
                .ab-root {
                    border: 1px solid #dfe7f5;
                    border-radius: 4px;
                    background: #f7faff;
                    max-height: 480px;
                    overflow-y: auto;
                }
                .ab-root::-webkit-scrollbar { width: 6px; }
                .ab-root::-webkit-scrollbar-track { background: #f7faff; }
                .ab-root::-webkit-scrollbar-thumb { background: #b3bfd1; border-radius: 3px; }
                .ab-root::-webkit-scrollbar-thumb:hover { background: #7f8fa4; }
                .ab-header {
                    padding: 12px 16px;
                    font-weight: 600;
                    font-size: 14px;
                    color: #191530;
                    border-bottom: 1px solid #dfe7f5;
                    background: #f7faff;
                    border-radius: 4px 4px 0 0;
                }
                .ab-loading {
                    padding: 24px;
                    text-align: center;
                    color: #7f8fa4;
                    animation: ab-pulse 1.5s ease-in-out infinite;
                }
                @keyframes ab-pulse {
                    0%, 100% { opacity: 1; }
                    50% { opacity: 0.5; }
                }
                .ab-error {
                    padding: 24px;
                    text-align: center;
                    color: #c0392b;
                    font-size: 12px;
                }
                .ab-category {
                    border-bottom: 1px solid #dfe7f5;
                }
                .ab-cat-title {
                    padding: 8px 16px;
                    font-weight: 600;
                    cursor: pointer;
                    background: #f7faff;
                    user-select: none;
                    color: #191530;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    transition: background-color 150ms ease-out;
                }
                .ab-cat-title:hover { background: #ebf0fa; }
                .ab-cat-title svg {
                    flex-shrink: 0;
                    transition: transform 150ms ease-out;
                }
                .ab-cat-title.open svg {
                    transform: rotate(90deg);
                }
                .ab-questions { display: none; }
                .ab-questions.open { display: block; }
                .ab-question {
                    padding: 8px 16px 8px 32px;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    color: #191530;
                    transition: background-color 150ms ease-out;
                }
                .ab-question:hover { background: #ebf0fa; }
                .ab-dp-list { padding-left: 24px; }
                .ab-dp {
                    padding: 6px 16px 6px 32px;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    color: #191530;
                    transition: background-color 150ms ease-out;
                }
                .ab-dp:hover { background: #ebf0fa; }
                .ab-dp .cb, .ab-question .cb {
                    width: 16px;
                    height: 16px;
                    border: 1.5px solid #191530;
                    border-radius: 3px;
                    flex-shrink: 0;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    transition: all 150ms ease-out;
                    background: #fff;
                }
                .ab-dp .cb.checked, .ab-question .cb.checked {
                    background: #de1b76;
                    border-color: #de1b76;
                }
            </style>
            <div class="ab-root">
                <div class="ab-header">Attribute Browser</div>
                <div class="ab-loading" id="ab-content">Loading attributes\u2026</div>
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
            if (el) {
                el.className = "ab-error";
                el.textContent = "Failed to load attributes.";
            }
        }
    }

    private static CHEVRON_SVG = `<svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M4.5 2.5L8 6L4.5 9.5" stroke="#191530" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
    private static CHECK_SVG = `<svg width="10" height="10" viewBox="0 0 10 10" fill="none"><path d="M2 5.5L4 7.5L8 3" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

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
            title.innerHTML = `${MockAttributeBrowser.CHEVRON_SVG}<span>${cat.name}</span>`;

            const questionsEl = document.createElement("div");
            questionsEl.className = "ab-questions";

            title.addEventListener("click", () => {
                const isOpen = questionsEl.classList.toggle("open");
                title.classList.toggle("open", isOpen);
            });

            for (const q of cat.questions) {
                const qRow = document.createElement("div");
                qRow.className = "ab-question";
                qRow.innerHTML = `<span class="cb"></span><span>${q.name}</span>`;

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
                                    dpRow.innerHTML = `<span class="cb"></span><span>${dp.name}</span>`;
                                    dpRow.addEventListener("click", (e) => {
                                        e.stopPropagation();
                                        const cb = dpRow.querySelector(".cb");
                                        if (cb) {
                                            const wasChecked =
                                                cb.classList.toggle("checked");
                                            cb.innerHTML = wasChecked
                                                ? MockAttributeBrowser.CHECK_SVG
                                                : "";
                                        }
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

    private static CHECK_SVG = `<svg width="10" height="10" viewBox="0 0 10 10" fill="none"><path d="M2 5.5L4 7.5L8 3" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

    private render() {
        this.shadow.innerHTML = `
            <style>
                :host {
                    display: block;
                    font-family: Faktum, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    font-size: 13px;
                    color: #191530;
                }
                .aub-root {
                    border: 1px solid #dfe7f5;
                    border-radius: 4px;
                    background: #f7faff;
                    max-height: 480px;
                    overflow-y: auto;
                }
                .aub-root::-webkit-scrollbar { width: 6px; }
                .aub-root::-webkit-scrollbar-track { background: #f7faff; }
                .aub-root::-webkit-scrollbar-thumb { background: #b3bfd1; border-radius: 3px; }
                .aub-root::-webkit-scrollbar-thumb:hover { background: #7f8fa4; }
                .aub-header {
                    padding: 12px 16px;
                    font-weight: 600;
                    font-size: 14px;
                    color: #191530;
                    border-bottom: 1px solid #dfe7f5;
                    background: #f7faff;
                    border-radius: 4px 4px 0 0;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }
                .aub-loading {
                    padding: 24px;
                    text-align: center;
                    color: #7f8fa4;
                    animation: aub-pulse 1.5s ease-in-out infinite;
                }
                @keyframes aub-pulse {
                    0%, 100% { opacity: 1; }
                    50% { opacity: 0.5; }
                }
                .aub-error {
                    padding: 24px;
                    text-align: center;
                    color: #c0392b;
                    font-size: 12px;
                }
                .aub-empty {
                    padding: 24px;
                    text-align: center;
                    color: #7f8fa4;
                    font-style: italic;
                    font-size: 13px;
                }
                .aub-section {
                    border-bottom: 1px solid #dfe7f5;
                }
                .aub-section-title {
                    padding: 8px 16px;
                    font-weight: 600;
                    font-size: 11px;
                    text-transform: uppercase;
                    color: #526482;
                    background: #f7faff;
                    letter-spacing: 0.8px;
                }
                .aub-item {
                    padding: 12px 16px;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    border-bottom: 1px solid #dfe7f5;
                    color: #191530;
                    transition: background-color 150ms ease-out;
                }
                .aub-item:hover { background: #ebf0fa; }
                .aub-item .cb {
                    width: 16px;
                    height: 16px;
                    border: 1.5px solid #191530;
                    border-radius: 3px;
                    flex-shrink: 0;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    transition: all 150ms ease-out;
                    background: #fff;
                }
                .aub-item .cb.checked {
                    background: #de1b76;
                    border-color: #de1b76;
                }
                .aub-item-name { flex: 1; }
                .aub-item-badge {
                    font-size: 11px;
                    padding: 2px 8px;
                    border-radius: 10px;
                    background: #b9e1f9;
                    color: #007cb6;
                    font-weight: 500;
                }
                .aub-btn {
                    padding: 6px 12px;
                    background: #de1b76;
                    color: #fff;
                    border: none;
                    border-radius: 4px;
                    cursor: pointer;
                    font-size: 12px;
                    font-weight: 600;
                    font-family: inherit;
                    transition: background-color 150ms ease-out;
                }
                .aub-btn:hover { background: #a40f58; }
            </style>
            <div class="aub-root">
                <div class="aub-header">
                    <span>Audience Browser</span>
                    <button class="aub-btn" id="aub-create">+ Create</button>
                </div>
                <div class="aub-loading" id="aub-content">Loading audiences\u2026</div>
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
            if (el) {
                el.className = "aub-error";
                el.textContent = "Failed to load audiences.";
            }
        }
    }

    private renderAudiences(audiences: Array<any>) {
        const container = this.shadow.getElementById("aub-content");
        if (!container) return;
        container.className = "";
        container.innerHTML = "";

        if (audiences.length === 0) {
            container.innerHTML = `<div class="aub-empty">No saved audiences yet.</div>`;
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
        const badge = audience.shared ? `<span class="aub-item-badge">Shared</span>` : "";

        row.innerHTML = `<span class="cb${isStaged ? " checked" : ""}">${isStaged ? MockAudienceBrowser.CHECK_SVG : ""}</span><span class="aub-item-name">${audience.name}</span>${badge}`;

        row.addEventListener("click", () => {
            const cb = row.querySelector(".cb");
            if (cb) {
                const wasChecked = cb.classList.toggle("checked");
                cb.innerHTML = wasChecked ? MockAudienceBrowser.CHECK_SVG : "";
            }
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
                :host {
                    display: block;
                    font-family: Faktum, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    font-size: 12px;
                    color: #526482;
                }
                .expr {
                    padding: 8px 12px;
                    background: #f7faff;
                    border-radius: 4px;
                    border: 1px solid #dfe7f5;
                }
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
