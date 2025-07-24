import call from "./call";
import * as events from "./events";

type TryableEvents = "try-close" | "try-hide" | "try-show";
type Events = TryableEvents | "show" | "hide";
type Callback<T extends Events> = T extends TryableEvents
    ? () => boolean | Promise<boolean>
    : () => void;
const emitter = new events.Emitter("window");
async function addListener<K extends Events>(
    event: K,
    callback: Callback<K>,
    once: boolean = false
) {
    if (event === "try-close" || event === "try-hide" || event === "try-show") {
        events.addTryableListener(
            await call("window.getId"),
            event,
            callback as Callback<TryableEvents>,
            once
        );
    } else {
        if (once) emitter.once(event, callback);
        else emitter.on(event, callback);
    }
}

async function removeListener<K extends Events>(event: K, callback: Callback<K>) {
    if (event === "try-close" || event === "try-hide" || event === "try-show") {
        events.removeTryableListener(
            await call("window.getId"),
            event,
            callback as Callback<TryableEvents>
        );
    } else {
        emitter.off(event, callback);
    }
}

export function on<K extends Events>(event: K, callback: Callback<K>) {
    return addListener(event, callback);
}
export function off<K extends Events>(event: K, callback: Callback<K>) {
    return removeListener(event, callback);
}

export function once<K extends Events>(event: K, callback: Callback<K>) {
    return addListener(event, callback, true);
}

export type Options = {
    title: string;
    class: string;
    resizable: boolean;
    backgroundTransparent: boolean;
    hidden: boolean;
    width: number;
    height: number;
};
function _init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        title: options.title ?? "MikaShell Window",
        class: options.class ?? "mika-shell",
        resizable: options.resizable ?? true,
        backgroundTransparent: options.backgroundTransparent ?? false,
        hidden: options.hidden ?? false,
        width: options.width ?? 0,
        height: options.height ?? 0,
    };
    return call("window.init", opt);
}
export function init(options: Partial<Options> = {}): Promise<void> {
    if (options.resizable !== true) {
        return new Promise((resolve, reject) => {
            window.addEventListener("load", () => {
                _init(options).then(resolve).catch(reject);
            });
        });
    } else {
        return _init(options);
    }
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
export function openDevTools(): Promise<void> {
    return call("window.openDevTools");
}
export function getSize(): Promise<{ width: number; height: number }> {
    return call("window.getSize");
}
export function setSize(width: number, height: number): Promise<void> {
    return call("window.setSize", width, height);
}
export function setInputRegion(): Promise<void> {
    return call("layer.setInputRegion");
}
export function getScale(): Promise<number> {
    return call("layer.getScale");
}
