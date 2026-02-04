/**
 * Standalone entry point for local development.
 * Bypasses single-spa and loads the Elm app directly.
 */
import * as ElmDebugger from "elm-debug-transformer";

require("@webcomponents/webcomponentsjs/webcomponents-bundle.js");
require("@webcomponents/webcomponentsjs/custom-elements-es5-adapter.js");

// Styles
require("./main.scss");

// Web Components (stubs)
require("../../webcomponents");
require("../../custom-elements/x-cooltip/component.ts");
require("../../custom-elements/x-cooltip/style.scss");
require("../../custom-elements/x-simplebar/component.ts");
require("../../custom-elements/x-simplebar/style.scss");
require("../../custom-elements/x-resize-observer/component.ts");

ElmDebugger.register({ limit: 1000000 });

// Stub analytics on window
// @ts-ignore
window.analytics = {
    track: (...args) => console.log("[analytics.track]", ...args),
    batch: (...args) => console.log("[analytics.batch]", ...args)
};

// Load the Elm app
import(
    /* webpackChunkName: "crosstabs-elm" */
    /* webpackMode: "eager" */
    // @ts-ignore
    "./src/Main"
).then(({ Elm }) => {
    const container = document.getElementById("elm-app");
    if (!container) {
        throw new Error("Missing #elm-app element");
    }

    const element = document.createElement("div");
    const wrapper = document.createElement("div");
    wrapper.className = "xb2-wrapper";
    wrapper.appendChild(element);
    container.appendChild(wrapper);

    const flags = {
        token: "mock-token",
        user: {
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
        },
        env: "development",
        platform2Url: "http://localhost:3005",
        referrer: "http://localhost:3005",
        feature: null,
        pathPrefix: null,
        helpMode: false,
        revision: "local-dev"
    };

    const app = Elm.Main.init({
        node: element,
        flags: flags
    });

    // Send mount signal
    if (app.ports.mountXB2) {
        // Subscribe to mountedXB2 to know when mounting completes
        if (app.ports.mountedXB2) {
            app.ports.mountedXB2.subscribe(() => {
                console.log("[standalone] Elm app mounted");
            });
        }

        // Subscribe to unmountedXB2 (no-op for standalone)
        if (app.ports.unmountedXB2) {
            app.ports.unmountedXB2.subscribe(() => {
                console.log("[standalone] Elm app unmounted");
            });
        }

        app.ports.mountXB2.send(null);
    }

    // Wire navigateToXB2 → pushState + routeChangedXB2
    if (app.ports.navigateToXB2) {
        app.ports.navigateToXB2.subscribe((url: string) => {
            history.pushState(null, "", url);
            if (app.ports.routeChangedXB2) {
                app.ports.routeChangedXB2.send(window.location.href);
            }
        });
    }

    // Handle browser back/forward
    window.addEventListener("popstate", () => {
        if (app.ports.routeChangedXB2) {
            app.ports.routeChangedXB2.send(window.location.href);
        }
    });

    // Stub: openNewWindowXB2
    if (app.ports.openNewWindowXB2) {
        app.ports.openNewWindowXB2.subscribe((url: string) => {
            window.open(url, "_blank");
        });
    }

    // Stub: interruptRoutingStatusXB2 (no-op in standalone)
    if (app.ports.interruptRoutingStatusXB2) {
        app.ports.interruptRoutingStatusXB2.subscribe(() => {});
    }

    // Stub: setXBProjectCheckBeforeLeave
    if (app.ports.setXBProjectCheckBeforeLeave) {
        app.ports.setXBProjectCheckBeforeLeave.subscribe((edited: boolean) => {
            if (edited) {
                window.onbeforeunload = () => "You have unsaved changes.";
            } else {
                window.onbeforeunload = null;
            }
        });
    }

    // Stub: openChatWithErrorId (intercom)
    if (app.ports.openChatWithErrorId) {
        app.ports.openChatWithErrorId.subscribe((errorId) => {
            console.log("[standalone] openChatWithErrorId:", errorId);
        });
    }

    // Stub: track / batch analytics ports
    if (app.ports.track) {
        app.ports.track.subscribe((args) => {
            console.log("[analytics.track port]", args);
            if (args && args[0] === "Unexpected Error") {
                console.warn(
                    "[UNEXPECTED ERROR DETAIL]",
                    JSON.stringify(args[1], null, 2)
                );
            }
        });
    }
    if (app.ports.batch) {
        app.ports.batch.subscribe((args) => {
            console.log("[analytics.batch port]", args);
        });
    }

    // Stub: addHostAndCopyToClipboard
    if (app.ports.addHostAndCopyToClipboard) {
        app.ports.addHostAndCopyToClipboard.subscribe((url: string) => {
            navigator.clipboard.writeText(window.location.origin + url);
        });
    }

    // Stub: selectTextInFieldXB2
    if (app.ports.selectTextInFieldXB2) {
        app.ports.selectTextInFieldXB2.subscribe((elementId: string) => {
            try {
                // @ts-ignore
                document.getElementById(elementId)?.select();
            } catch (e) {}
        });
    }

    // Stub: debouncedScrollEvent
    if (app.ports.debouncedScrollEvent) {
        app.ports.debouncedScrollEvent.subscribe(() => {});
    }

    // Stub: setConfirmMsgBeforeLeavePage
    if (app.ports.setConfirmMsgBeforeLeavePage) {
        app.ports.setConfirmMsgBeforeLeavePage.subscribe(() => {});
    }

    console.log("[standalone] Crosstab Builder XB2 initialized");
});
