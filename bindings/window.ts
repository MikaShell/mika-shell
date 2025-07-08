import call from "./call";
export type Options = {
    title: string;
    resizable: boolean;
    backgroundTransparent: boolean;
    hidden: boolean;
};

export function init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        title: options.title ?? "AikaShell Window",
        resizable: options.resizable ?? true,
        backgroundTransparent: options.backgroundTransparent ?? false,
        hidden: options.hidden ?? false,
    };
    return call("window.init", opt);
}
export function show(): Promise<void> {
    return call("window.show");
}
export function hide(): Promise<void> {
    return call("window.hide");
}
export function close(): Promise<void> {
    return call("window.close");
}
import * as events from "./events";

type Events = {
    close: () => boolean | Promise<boolean>;
    hide: () => boolean | Promise<boolean>;
    show: () => boolean | Promise<boolean>;
};
async function addListener<K extends keyof Events>(
    event: K,
    callback: Events[K],
    once: boolean = false
) {
    if (event === "close" || event === "hide" || event === "show") {
        events.addTryableListener(await call("window.getId"), event, callback, once);
    } else {
        events.addEventListener(event, callback, once);
    }
}

async function removeListener<K extends keyof Events>(event: K, callback: Events[K]) {
    if (event === "close" || event === "hide" || event === "show") {
        events.removeTryableListener(await call("window.getId"), event, callback);
    } else {
        events.removeEventListener(event, callback);
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
