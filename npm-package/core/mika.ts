import call from "./call";
import * as events from "./events";
import { Mika } from "./events-define";

function setHost_(name: string) {
    if (name.startsWith("/")) {
        return "/" + globalThis.location.host + name;
    } else {
        return globalThis.location.host + "." + name;
    }
}
// Open a webview, and wait for the webview to close before returning.
// If `setHost` is `true`, it will automatically add the host prefix to the url, which is consistent with the command line behavior, ensuring that the url of the opened webview is correct.
export function open(name: string, setHost: boolean = true): Promise<void> {
    return call("mika.open", setHost ? setHost_(name) : name);
}
// Open a webview, the promise will return the id of the webview when the webview is opened.
// If `setHost` is `true`, it will automatically add the host prefix to the url, which is consistent with the command line behavior, ensuring that the url of the opened webview is correct.
export function openAsync(name: string, setHost: boolean = true): Promise<number> {
    return call("mika.openAsync", setHost ? setHost_(name) : name);
}
export function openDevTools(id: number): Promise<void> {
    return call("mika.openDevTools", id);
}
export function close(id: number): Promise<void> {
    return call("mika.close", id);
}
export function show(id: number): Promise<void> {
    return call("mika.show", id);
}
export function hide(id: number): Promise<void> {
    return call("mika.hide", id);
}
export function forceShow(id: number): Promise<void> {
    return call("mika.forceShow", id);
}
export function forceHide(id: number): Promise<void> {
    return call("mika.forceHide", id);
}
export function forceClose(id: number): Promise<void> {
    return call("mika.forceClose", id);
}
export function getConfigDir(): Promise<string> {
    return call("mika.getConfigDir");
}
export function list(): Promise<WebviewInfo[]> {
    return call("mika.list");
}
function dispatch(event: number): boolean {
    var cando = true;
    if (listeners.has(event)) {
        listeners.get(event)?.forEach(async (callback) => {
            const result = callback(cando);
            if (result instanceof Promise) {
                cando = cando && (await result) !== false;
            } else {
                cando = cando && result !== false;
            }
        });
    }
    if (onceListeners.has(event)) {
        onceListeners.get(event)?.forEach(async (callback) => {
            const result = callback(cando);
            if (result instanceof Promise) {
                cando = cando && (await result) !== false;
            } else {
                cando = cando && result !== false;
            }
        });
        onceListeners.delete(event);
    }
    return cando;
}
events.on(Mika["show-request"], async (id: number) => {
    if (dispatch(Mika["show-request"])) forceShow(id);
});
events.on(Mika["hide-request"], (id: number) => {
    if (dispatch(Mika["hide-request"])) forceHide(id);
});
events.on(Mika["close-request"], (id: number) => {
    if (dispatch(Mika["close-request"])) forceClose(id);
});
export interface WebviewInfo {
    id: number;
    type: "none" | "layer" | "window" | "popup";
    uri: string;
    title: string;
    visible: boolean;
    alias: string;
}

type EventMap = {
    [K in keyof typeof Mika]: K extends "open"
        ? (data: WebviewInfo) => void
        : K extends "hide" | "close" | "show"
        ? (id: number) => void
        : K extends "show-request" | "hide-request" | "close-request"
        ? (prev: boolean) => boolean | Promise<boolean>
        : never;
};
const listeners: Map<number, Array<(prev: boolean) => boolean | Promise<boolean>>> = new Map(); // only handle xxx-request event
const onceListeners: Map<number, Array<(prev: boolean) => boolean | Promise<boolean>>> = new Map(); // only handle xxx-request event

type Events = "open" | "show" | "close" | "hide";

export function on<K extends Events>(event: K, callback: EventMap[K]) {
    const e = event as string;
    if (e === "show-request" || e === "hide-request" || e === "close-request") {
        const cb = callback as () => boolean | Promise<boolean>;
        if (!listeners.has(Mika[event])) {
            listeners.set(Mika[event], []);
        }
        listeners.get(Mika[event])?.push(cb);
        return;
    }
    events.on(Mika[event], callback);
}
export function off<K extends Events>(event: K, callback: EventMap[K]) {
    const e = event as string;
    if (e === "show-request" || e === "hide-request" || e === "close-request") {
        const cb = callback as () => boolean | Promise<boolean>;
        if (listeners.has(Mika[event])) {
            const index = listeners.get(Mika[event])?.indexOf(cb);
            if (index !== undefined && index >= 0) {
                listeners.get(Mika[event])?.splice(index, 1);
            }
        }
        if (onceListeners.has(Mika[event])) {
            const index = onceListeners.get(Mika[event])?.indexOf(cb);
            if (index !== undefined && index >= 0) {
                onceListeners.get(Mika[event])?.splice(index, 1);
            }
        }
        return;
    }
    events.off(Mika[event], callback);
}
export function once<K extends Events>(event: K, callback: EventMap[K]) {
    const e = event as string;
    if (e === "show-request" || e === "hide-request" || e === "close-request") {
        const cb = callback as () => boolean | Promise<boolean>;
        if (!onceListeners.has(Mika[event])) {
            onceListeners.set(Mika[event], []);
        }
        onceListeners.get(Mika[event])?.push(cb);
        return;
    }
    events.once(Mika[event], callback);
}
