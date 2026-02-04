import Intercom from "../_stubs/platform2-lib/intercom";

export default (app) => {
    if (Intercom) {
        window.addEventListener(Intercom.STATE_CHANGED_EVENT, (event) => {
            // @ts-ignore
            app.ports.setChatVisibility.send(event.detail.isOpened);
        });
    }
};
