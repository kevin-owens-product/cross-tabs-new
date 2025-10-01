export const getEnvironment = (ENV) => {
    if ("environment" in ENV) return ENV.environment;
    if ("env" in ENV) return ENV.env;
    throw "The ENV object doesn't contain `env` or `environment` field!";
};

export const host = (environment) => {
    switch (environment) {
        case "production":
            return "https://api.globalwebindex.com";
        case "staging":
            return "https://api-staging.globalwebindex.com";
        case "alpha":
            return "https://api-alpha.globalwebindex.com";
        case "testing":
            return "https://api-testing.globalwebindex.com";
        case "development":
            return "https://api-testing.globalwebindex.com";
        default:
            throw `Unknown environment: "${environment}"!`;
    }
};

export const susiHost = (environment) => {
    switch (environment) {
        case "production":
            return "https://signin.globalwebindex.com";
        case "staging":
            return "https://signin-staging.globalwebindex.com";
        case "alpha":
            return "https://signin-alpha.globalwebindex.com";
        case "testing":
            return "https://signin-testing.globalwebindex.com";
        case "development":
            return "https://signin-testing.globalwebindex.com";
        default:
            throw `Unknown environment: "${environment}"!`;
    }
};

export const rmpPanelHost = (environment) => {
    switch (environment) {
        case "production":
            return "https://panel-ui.globalwebindex.com";
        case "staging":
            return "https://panel-ui-staging.globalwebindex.com";
        case "alpha":
            return "https://panel-ui-staging.globalwebindex.com";
        case "testing":
            return "https://panel-ui-staging.globalwebindex.com"; // staging not a typo
        case "development":
            return "https://panel-ui-staging.globalwebindex.com"; // staging not a typo
        default:
            throw `Unknown environment: "${environment}"!`;
    }
};

export const tokenCookieName = (token_type) => (environment) => {
    switch (environment) {
        case "production":
            return `${token_type}_gwi`;
        case "staging":
            return `${token_type}_gwi_staging`;
        case "alpha":
            return `${token_type}_gwi_staging`; // staging not a typo
        case "testing":
            return `${token_type}_gwi_testing`;
        case "development":
            return `${token_type}_gwi_testing`;
        // ^ no such cookie for development, but null would lead to problems with Cookies.get(null)
        default:
            throw `Unknown environment: "${environment}"!`;
    }
};

export const authTokenCookieName = tokenCookieName("auth");
export const refreshTokenCookieName = tokenCookieName("refresh");

export const authMasqueradingTokenCookieName = (environment) => {
    switch (environment) {
        case "production":
            return "auth_gwi_masquerading";
        case "staging":
            return "auth_gwi_staging_masquerading";
        case "alpha":
            return "auth_gwi_alpha_masquerading"; 
        case "testing":
            return "auth_gwi_testing_masquerading";
        case "development":
            return "auth_gwi_development_masquerading";
        // ^ no such cookie for development, but null would lead to problems with Cookies.get(null)
        default:
            throw `Unknown environment: "${environment}"!`;
    }
};

export const domain = "globalwebindex.com";
export const authTokenUrlParam = "access_token";
export const refreshTokenUrlParam = "refresh_token";

export const removeUrlParam = (param) => {
    const params = new URLSearchParams(window.location.search);
    params.delete(param);
    // @ts-ignore
    const newLocation = new URL(window.location);
    newLocation.search = params.toString();

    window.history.pushState(null, "Removed URL param", newLocation);
};

export const navigateTo = (route, send) => {
    const location = window.location;
    const routeWithOrigin = route.indexOf("://") > -1 ? route : location.origin + route;
    const url = new URL(routeWithOrigin);
    const query = url.search.substring(1);
    const fragment = url.hash.substring(1);

    if (url.origin !== location.origin) {
        location.href = url.href;
    } else {
        send({
            protocolIsHttps: url.protocol === "https:",
            host: url.hostname,
            port_: url.port ? parseInt(url.port) : null,
            path: url.pathname,
            query: query,
            fragment: fragment
        });
    }
};

// Hack to get DOMRect of event target - Thx @wolfadex! ♥
Object.defineProperty(Element.prototype, "__getBoundingClientRect", {
    get() {
        return this.getBoundingClientRect();
    },
    configurable: true
});
