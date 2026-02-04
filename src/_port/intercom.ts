import { handlers } from "./helpers";
import Intercom from "../_stubs/platform2-lib/intercom";

const openChat = (app) => () => {
    Intercom.show();
};

const closeChat = (app) => () => {
    Intercom.hide();
};

const openChatWithErrorId = (app) => (errorId: string | null) => {
    if (errorId !== null) {
        Intercom.showWithMessage(
            `Trace ID: ${errorId} \n\n Hi, can you assist me with the above issue? 👋`
        );
    } else {
        Intercom.show();
    }
};

export default handlers({
    openChat,
    closeChat,
    openChatWithErrorId
});
