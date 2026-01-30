import * as helpers from "./helpers";
import debounce from "debounce";
import Bowser from "bowser";
import { p2EnvPlatform } from "../_helpers/platform";

const identify = (ENV) => {
    if (ENV.is_headless_test) return;
    if (ENV.user.plan_handle === "open_access_view_only") return;

    const body = JSON.stringify({
        traits: { proPlan: ENV.user.plan_handle },
        app_name: ENV.app_name,
        user_id: ENV.user.id,
        user_email: ENV.user.email
    });

    fetch(helpers.host(helpers.getEnvironment(ENV)) + "/v1/analytics/identify", {
        method: "POST",
        body: body,
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${ENV.token}`,
            "Keep-Alive": "timeout=10, max=1"
        }
    });
};

const sendLastPlatformUsed = debounce(
    (ENV) =>
        fetch(
            `${helpers.host(helpers.getEnvironment(ENV))}/v1/users-next/users/${
                ENV.user.id
            }/last_platform_used`,
            {
                method: "PUT",
                body: JSON.stringify({
                    platform: ENV.platform === p2EnvPlatform ? "platform2" : "platform1"
                }),
                headers: {
                    "Content-Type": "application/json",
                    Authorization: `Bearer ${ENV.token}`,
                    "Keep-Alive": "timeout=10, max=1"
                }
            }
        ),
    60 * 1000,
    true
);

const nullAsEmptyString = (v) => (v === null ? "" : v);

const extendedProperties = (basicProperties, ENV) => {
    const browser = Bowser.getParser(window.navigator.userAgent).getBrowser();

    return {
        ...basicProperties,
        plan_handle_snapshot: ENV.user.plan_handle,
        user_agent: window.navigator.userAgent,
        browser_name: browser.name,
        browser_version: browser.version,
        screen_height: window.screen.height,
        screen_width: window.screen.width
    };
};

const track = (ENV, eventName, properties = {}) => {
    if (ENV.is_headless_test) return;
    if (ENV.user.plan_handle === "open_access_view_only") return;

    const body = JSON.stringify({
        traits: {},
        app_name: ENV.app_name,
        user_id: ENV.user.id,
        user_email: ENV.user.email,
        event_name: eventName,
        timestamp: Date.now(),
        properties: extendedProperties(properties, ENV)
    });

    fetch(helpers.host(helpers.getEnvironment(ENV)) + "/v1/analytics/track", {
        method: "POST",
        body: body,
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${ENV.token}`,
            "Keep-Alive": "timeout=10, max=1"
        }
    });

    sendLastPlatformUsed(ENV);
};

const batch = (ENV, events) => {
    if (ENV.is_headless_test) return;
    if (ENV.user.plan_handle === "open_access_view_only") return;

    const body = JSON.stringify(
        events.map((event) => {
            const eventName = event[0];
            const properties = event[1];

            return {
                type: "track",
                traits: {},
                app_name: ENV.app_name,
                user_id: ENV.user.id,
                user_email: ENV.user.email,
                event_name: eventName,
                timestamp: Date.now(),
                properties: extendedProperties(properties, ENV)
            };
        })
    );

    fetch(helpers.host(helpers.getEnvironment(ENV)) + "/v1/analytics/batch", {
        method: "POST",
        body: body,
        headers: {
            "Content-Type": "application/json",
            "Keep-Alive": "timeout=10, max=1",
            Authorization: `Bearer ${ENV.token}`
        }
    }).catch((e) => {
        console.error("Error fetching analytics", e, events);
    });

    sendLastPlatformUsed(ENV);
};

export default (ENV) => {
    return new Promise(function (resolve) {
        identify(ENV);
        // @ts-ignore
        window.analytics = {
            track: track.bind(null, ENV),
            batch: batch.bind(null, ENV)
        };
        resolve(ENV);
    });
};
