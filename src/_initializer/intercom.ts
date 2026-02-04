import Intercom from "../_stubs/platform2-lib/intercom";

export default (ENV) => {
    if (!ENV.keys.intercom || !ENV.user || ENV.user.plan_handle == "student") {
        return ENV;
    }

    Intercom;

    return ENV;
};
