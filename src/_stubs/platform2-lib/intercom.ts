/**
 * Stub for @globalwebindex/platform2-lib/dist/intercom
 * No-op Intercom interface for local development.
 */
const Intercom = {
    show() {},
    hide() {},
    showWithMessage(_msg: string) {},
    STATE_CHANGED_EVENT: "intercom:state-changed"
};

export default Intercom;
