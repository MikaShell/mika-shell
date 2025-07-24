import call from "./call";

interface Listener {
    callback: (data: any) => void;
    once: boolean;
}
const listeners: Map<string, Listener[]> = new Map();
function dispatchEvent(event: any) {
    const name: string = event.detail.name;
    const data: any = event.detail.data;
    const callbacks = listeners.get(name) || [];
    const needRemove: Listener[] = [];
    callbacks.forEach((listener) => {
        if (listener.once) {
            needRemove.push(listener);
        }
        listener.callback(data);
    });
    needRemove.forEach((listener) => {
        removeEventListener(name, listener.callback);
    });
    if (callbacks.length === 0) {
        listeners.delete(name);
    }
    if (listeners.size === 0) window.removeEventListener("mika-shell-event", dispatchEvent);
}
type TryableCallback = () => boolean | Promise<boolean>;
type TryableListener = { action: string; callback: TryableCallback; once: boolean };
const canTryListeners: Map<number, TryableListener[]> = new Map();
async function dispatchTryableEvent(id: number, action: string) {
    const handlers = canTryListeners.get(id) || [];
    const needRemove: TryableListener[] = [];
    let canDo = true;
    for (const handler of handlers) {
        if (handler.action !== action) continue;
        if (handler.once) needRemove.push(handler);
        const result = handler.callback();
        if (result instanceof Promise) {
            canDo = canDo && (await result) !== false;
        } else {
            canDo = canDo && result !== false;
        }
    }
    if (handlers.length === 0) {
        canTryListeners.delete(id);
    }
    if (needRemove.length > 0) {
        for (const handler of needRemove) {
            const index = handlers.indexOf(handler);
            if (index >= 0) handlers.splice(index, 1);
        }
    }
    if (canDo) {
        if (action === "try-close") call("mika.forceClose", id);
        else if (action === "try-show") call("mika.forceShow", id);
        else if (action === "try-hide") call("mika.forceHide", id);
    }
}
export function addTryableListener(
    id: number,
    action: "try-close" | "try-show" | "try-hide",
    callback: () => boolean | Promise<boolean>,
    once: boolean = false
) {
    canTryListeners.set(id, [...(canTryListeners.get(id) || []), { action, callback, once }]);
}
export function removeTryableListener(
    id: number,
    action: "try-close" | "try-show" | "try-hide",
    callback: () => boolean | Promise<boolean>
) {
    const handlers = canTryListeners.get(id) || [];
    const index = handlers.findIndex(
        (handler) => handler.callback === callback && handler.action === action
    );
    if (index >= 0) {
        handlers.splice(index, 1);
        canTryListeners.set(id, handlers);
    }
    if (handlers.length === 0) {
        canTryListeners.delete(id);
    }
}
function addEventListener(name: string, callback: (data: any) => void, once: boolean = false) {
    if (listeners.size === 0) window.addEventListener("mika-shell-event", dispatchEvent);
    listeners.set(name, [...(listeners.get(name) || []), { callback, once }]);
}
function removeEventListener(name: string, callback: (data: any) => void) {
    const callbacks = listeners.get(name) || [];
    const index = callbacks.findIndex((listener) => listener.callback === callback);
    if (index >= 0) {
        callbacks.splice(index, 1);
        listeners.set(name, callbacks);
    }
}
var isClosing = false;
addEventListener("mika-try-close", (id) => {
    if (isClosing) return;
    isClosing = true;
    dispatchTryableEvent(id, "try-close");
    isClosing = false;
});
var isShowing = false;
addEventListener("mika-try-show", (id) => {
    if (isShowing) return;
    isShowing = true;
    dispatchTryableEvent(id, "try-show");
    isShowing = false;
});
var isHiding = false;
addEventListener("mika-try-hide", (id) => {
    if (isHiding) return;
    isHiding = true;
    dispatchTryableEvent(id, "try-hide");
    isHiding = false;
});

export class Emitter {
    private listeners: Map<string, Function[]> = new Map();
    private onceListeners: Map<string, Function[]> = new Map();
    public init: () => void = () => {};
    public deinit: () => void = () => {};
    public onEmpty: (name: string) => void = () => {};
    private fullName(name: string) {
        return `${this.prifix}-${name}`;
    }
    constructor(private prifix: string) {
        this.dispatch = this.dispatch.bind(this);
        window.addEventListener("mika-shell-event", this.dispatch);
    }
    on(name: string, callback: Function) {
        if (this.listeners.size === 0 && this.onceListeners.size === 0) {
            this.init();
        }
        const name_ = this.fullName(name);
        this.listeners.set(name_, [...(this.listeners.get(name_) || []), callback]);
    }
    once(name: string, callback: Function) {
        if (this.onceListeners.size === 0) this.init();
        const name_ = this.fullName(name);
        this.onceListeners.set(name_, [...(this.onceListeners.get(name_) || []), callback]);
    }
    off(name: string, callback: Function) {
        const name_ = this.fullName(name);
        const listeners = this.listeners.get(name_) || [];
        const onceListeners = this.onceListeners.get(name_) || [];
        const index = listeners.indexOf(callback);
        if (index >= 0) listeners.splice(index, 1);
        const onceIndex = onceListeners.indexOf(callback);
        if (onceIndex >= 0) onceListeners.splice(onceIndex, 1);
        if (listeners.length === 0) this.listeners.delete(name_);
        if (onceListeners.length === 0) this.onceListeners.delete(name_);
        if (this.listeners.size === 0 && this.onceListeners.size === 0) {
            this.deinit();
            window.removeEventListener("mika-shell-event", this.dispatch);
        }
    }
    private async dispatch(event: any) {
        const name: string = event.detail.name;
        const data: any = event.detail.data;
        if (!name.startsWith(this.prifix)) return;
        const listeners = this.listeners.get(name) || [];
        const onceListeners = this.onceListeners.get(name) || [];
        listeners.forEach((callback) => callback(data));
        onceListeners.forEach((callback) => callback(data));
        this.onceListeners.delete(name);
        if (listeners.length === 0) {
            this.listeners.delete(name);
            this.onEmpty(name.replace(this.prifix + "-", ""));
        }
    }
}
