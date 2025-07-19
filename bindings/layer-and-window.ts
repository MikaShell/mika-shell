import call from "./call";
import * as events from "./events";

type Events = {
    close: () => boolean | Promise<boolean>;
    hide: () => boolean | Promise<boolean>;
    show: () => boolean | Promise<boolean>;
};
const emitter = new events.Emitter("window");
async function addListener<K extends keyof Events>(
    event: K,
    callback: Events[K],
    once: boolean = false
) {
    if (event === "close" || event === "hide" || event === "show") {
        events.addTryableListener(await call("window.getId"), event, callback, once);
    } else {
        if (once) emitter.once(event, callback);
        else emitter.on(event, callback);
    }
}

async function removeListener<K extends keyof Events>(event: K, callback: Events[K]) {
    if (event === "close" || event === "hide" || event === "show") {
        events.removeTryableListener(await call("window.getId"), event, callback);
    } else {
        emitter.off(event, callback);
    }
}

export function on<K extends keyof Events>(event: K, callback: Events[K]) {
    return addListener(event, callback);
}
export function off<K extends keyof Events>(event: K, callback: Events[K]) {
    return removeListener(event, callback);
}

export function once<K extends keyof Events>(event: K, callback: Events[K]) {
    return addListener(event, callback, true);
}
