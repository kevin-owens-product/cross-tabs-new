/**
   This files define interface specific to single-spa framework
   which make crosstab builder pluggable component of platform2-lib repository.

   This entry is meant to be compiled to AMD or Systemjs module
   with public interface containing:

   * bootstrap
   * mount
   * unmount
*/
import { ximport } from "@globalwebindex/platform2-lib";

import keysInit from "../../_initializer/keys";
import p2UrlInit from "../../_initializer/p2-url";
import analyticsInit from "../../_initializer/analytics";

import analyticsPorts from "../../_port/analytics";
import windowPorts from "../../_port/window";
import { p2EnvPlatform } from "../../_helpers/platform";
import beforeUnloadConfirmPorts from "../../_port/beforeunload-confirm";
import scrollPorts from "../../_port/scroll";
import selectTextInFieldPorts from "../../_port/selectTextInField";
import intercomPorts from "../../_port/intercom";
import accessTokenHandler from "../../_port/accessToken";
import clipboardPorts from "../../_port/clipboard";
import * as Sentry from "@sentry/browser";

import "regenerator-runtime/runtime";

import * as ElmDebugger from "elm-debug-transformer";

require("@webcomponents/webcomponentsjs/webcomponents-bundle.js");
require("@webcomponents/webcomponentsjs/custom-elements-es5-adapter.js");
// styles
require("./main.scss");

// New Web Components
require("../../webcomponents");
require("../../custom-elements/x-cooltip/component.ts");
require("../../custom-elements/x-cooltip/style.scss");
require("../../custom-elements/x-simplebar/component.ts");
require("../../custom-elements/x-simplebar/style.scss");
require("../../custom-elements/x-resize-observer/component.ts");

ElmDebugger.register({ limit: 1000000 });

// Sentry
// @ts-ignore
if (process.env.TARGET_ENV !== "development" && !Boolean(window.Sentry)) {
    Sentry.init({
        dsn: "https://8742bda92d694e6f8296c8bc514e98b7@o356571.ingest.us.sentry.io/4504486294978565",
        integrations: [
            Sentry.browserTracingIntegration(),
            Sentry.replayIntegration({
                maskAllText: false,
                blockAllMedia: false
            }),
            Sentry.thirdPartyErrorFilterIntegration({
                filterKeys: ["crosstabs"],
                behaviour: "drop-error-if-contains-third-party-frames"
            })
        ],
        tracesSampleRate: 0,
        tracePropagationTargets: ["localhost", /^\//],
        environment: process.env.TARGET_ENV,

        replaysSessionSampleRate: 0,
        replaysOnErrorSampleRate: 1.0
    });
}

// CONFIG DEFINITIONS
const styleHref = "/assets/crosstabs.css";

const state = {
    checkBeforeLeave: false,
    ignoreNextRouteChangeCounter: 0,
    lastUrl: "",
    currentUrl: ""
};

function getDomElement(domId) {
    const htmlId = domId !== undefined ? domId : "container";

    let domElement = document.getElementById(htmlId);
    if (!domElement) {
        domElement = document.createElement("div");
        domElement.id = htmlId;
        document.body.appendChild(domElement);
    }

    return domElement;
}

function initENV(props) {
    const ENV = JSON.parse(JSON.stringify(props));
    ENV.platform = ENV.platform || p2EnvPlatform;
    keysInit(ENV);
    p2UrlInit(ENV);
    return ENV;
}

// SINGLE-SPA INTERFACE LOGIC

/** Bootstrap function needs to handle provision of all resources
as well as take core of main intialization of the app.
*/
export function bootstrap(props) {
    return ximport(styleHref)
        .then(
            () =>
                import(
                    /* webpackChunkName: "crosstabs-elm" */
                    /* webpackMode: "eager" */
                    // @ts-ignore
                    "./src/Main"
                )
        )
        .then(({ Elm }) => {
            // Container element
            // Elm is going to rewrite this node so it disappears
            const element = document.createElement("div");
            const domElement = getDomElement(props.domId);
            domElement.innerHTML = "";

            // wrapper is a dom node we use to control the lifecycle
            const wrapper = document.createElement("div");
            wrapper.className = "xb2-wrapper";
            wrapper.appendChild(element);
            domElement.appendChild(wrapper);

            const ENV = initENV(props);

            const app = Elm.Main.init({
                node: element,
                flags: ENV // Using global state again
            });

            // @ts-ignore
            state.domEl = wrapper;
            // @ts-ignore
            state.app = app;
        });
}

/** Mount application should handle render of the DOM of the application
and hook to events / subscriptions which are not necessary un unmounted state.
*/
export function mount(props) {
    // @ts-ignore
    const { app, domEl } = state;

    const ENV = initENV(props);
    analyticsInit(ENV);

    return new Promise((resolve) => {
        const mountedHandler = async function () {
            app.ports.mountedXB2.unsubscribe(mountedHandler);
            // @ts-ignore
            resolve();
        };

        // @ts-ignore
        state.navigateTo = async function (str) {
            // @ts-ignore
            window.singleSpaNavigate(str);
        };

        // @ts-ignore
        state.checkBeforeLeaveSubscription = async function (edited) {
            state.checkBeforeLeave = edited;
        };

        // @ts-ignore
        state.routeChanged = function () {
            if (state.lastUrl !== window.location.href) {
                if (state.ignoreNextRouteChangeCounter <= 0) {
                    app.ports.routeChangedXB2.send(window.location.href);
                } else {
                    state.ignoreNextRouteChangeCounter--;
                }
            }
            state.lastUrl = window.location.href;
        };

        // @ts-ignore
        state.beforeRouting = (evt) => {
            if (
                state.checkBeforeLeave &&
                evt.detail.newUrl.indexOf("/crosstabs") === -1
            ) {
                evt.detail.cancelNavigation();
                /**
                 * This whole SPA whatever kernel thing is wird as ***, you have `before-routing-event`
                 * but even if it's before route change is already done and if you cancel it, it just simply
                 * jump back to previous route so there are two route changes triggered even if nothing should happen.
                 * And yes, I tried preventDefault and stopPropagation usual JS magic, but no luck here.
                 * So here comes this hack. It's terribly stupid, but because SPA is 4rd party lib,
                 * I did not see other reasonable option.
                 * */
                state.ignoreNextRouteChangeCounter = 2;

                new Promise((resolve, _reject) => {
                    // @ts-ignore
                    state.interruptRoutingStatusHandler = async (state) => {
                        if (state === true) {
                            _reject("Cancelled navigation");
                        } else {
                            // @ts-ignore
                            resolve();
                        }
                    };
                    app.ports.interruptRoutingStatusXB2.subscribe(
                        // @ts-ignore
                        state.interruptRoutingStatusHandler
                    );
                    app.ports.checkRouteInterruptionXB2.send(evt.detail.newUrl);
                })
                    .catch(() => {
                        // Do nothing so Promise does not appear as unhandled
                        return;
                    })
                    .finally(() => {
                        app.ports.interruptRoutingStatusXB2.unsubscribe(
                            // @ts-ignore
                            state.interruptRoutingStatusHandler
                        );
                    });
            }
            /** Another great behaviour of single-spa. If there is routing-event, but for different app
             *  (like going from Dashboards to reports/insights..) it will not fire `single-spa:routing-event`
             * for this APP. But `single-spa:before-routing-event` is still fired. What a intuitive behaviour.
             * So we need to set lastUrl here in case of different URL
             *
             * */
            if (evt.detail.newUrl.indexOf("/crosstabs") === -1) {
                state.lastUrl = window.location.href;
            }
        };

        // hook routing
        // @ts-ignore
        window.addEventListener("single-spa:routing-event", state.routeChanged);
        window.addEventListener(
            "single-spa:before-routing-event",
            // @ts-ignore
            state.beforeRouting
        );

        // Ports communication
        accessTokenHandler(app).init();
        app.ports.mountedXB2.subscribe(mountedHandler);
        // @ts-ignore
        app.ports.navigateToXB2.subscribe(state.navigateTo);
        app.ports.mountXB2.send(null);
        app.ports.setXBProjectCheckBeforeLeave.subscribe(
            // @ts-ignore
            state.checkBeforeLeaveSubscription
        );

        // Book a demo analytics listening
        window.addEventListener("CrosstabBuilder-bookDemoEvent", () => {
            app.ports.bookADemoButtonClicked.send(null);
        });

        // Splash screen events
        window.addEventListener("CrosstabBuilder-talkToAnExpertEvent", () => {
            app.ports.talkToAnExpertSplashEvent.send(null);
        });
        window.addEventListener("CrosstabBuilder-upgradeEvent", () => {
            app.ports.upgradeSplashEvent.send(null);
        });

        // @ts-ignore
        windowPorts.subscribeOpenNewWindowXB2(app);
        // @ts-ignore
        analyticsPorts.subscribeTrack(app);
        // @ts-ignore
        analyticsPorts.subscribeBatch(app);
        // @ts-ignore
        beforeUnloadConfirmPorts.subscribeSetConfirmMsgBeforeLeavePage(app);
        // @ts-ignore
        scrollPorts.subscribeDebouncedScrollEvent(app);
        // @ts-ignore
        selectTextInFieldPorts.subscribeSelectTextInFieldXB2(app);
        // @ts-ignore
        intercomPorts.subscribeOpenChatWithErrorId(app);
        // @ts-ignore
        clipboardPorts.subscribeAddHostAndCopyToClipboard(app);

        // DOM operation
        const domElement = getDomElement(props.domId);
        domElement.appendChild(domEl);
    });
}

/** Unmount should take care of destruction of DOM
including event handlers / subscriptions that are not needed in unmounted state.
*/
export function unmount(props) {
    // @ts-ignore
    const { app } = state;
    return new Promise((resolve) => {
        const unmountedHandler = async function () {
            // unsubscribe from ports
            accessTokenHandler(app).clear();
            app.ports.unmountedXB2.unsubscribe(unmountedHandler);
            // @ts-ignore
            app.ports.navigateToXB2.unsubscribe(state.navigateTo);
            app.ports.setXBProjectCheckBeforeLeave.unsubscribe(
                // @ts-ignore
                state.checkBeforeLeaveSubscription
            );

            // @ts-ignore
            analyticsPorts.unsubscribeTrack(app);
            // @ts-ignore
            analyticsPorts.unsubscribeBatch(app);
            // @ts-ignore
            beforeUnloadConfirmPorts.unsubscribeSetConfirmMsgBeforeLeavePage(app);
            // @ts-ignore
            scrollPorts.unsubscribeDebouncedScrollEvent(app);
            // @ts-ignore
            selectTextInFieldPorts.unsubscribeSelectTextInFieldXB2(app);
            // @ts-ignore
            intercomPorts.unsubscribeOpenChatWithErrorId(app);
            // @ts-ignore
            clipboardPorts.unsubscribeAddHostAndCopyToClipboard(app);

            window.removeEventListener(
                "single-spa:routing-event",
                // @ts-ignore
                state.routeChanged
            );
            window.removeEventListener(
                "single-spa:before-routing-event",
                // @ts-ignore
                state.beforeRouting
            );
            state.lastUrl = null;
            state.ignoreNextRouteChangeCounter = 0;
            // @ts-ignore
            resolve();
        };

        // Ports communication
        app.ports.unmountedXB2.subscribe(unmountedHandler);
        app.ports.unmountXB2.send(null);

        // DOM operation
        const domElement = getDomElement(props.domId);
        domElement.innerHTML = "";
    });
}
