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
        if (action === "close") call("mika.forceClose", id);
        else if (action === "show") call("mika.forceShow", id);
        else if (action === "hide") call("mika.forceHide", id);
    }
}
export function addTryableListener(
    id: number,
    action: "close" | "show" | "hide",
    callback: () => boolean | Promise<boolean>,
    once: boolean = false
) {
    canTryListeners.set(id, [...(canTryListeners.get(id) || []), { action, callback, once }]);
}
export function removeTryableListener(
    id: number,
    action: "close" | "show" | "hide",
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
export function addEventListener(
    name: string,
    callback: (data: any) => void,
    once: boolean = false
) {
    if (listeners.size === 0) window.addEventListener("mika-shell-event", dispatchEvent);
    listeners.set(name, [...(listeners.get(name) || []), { callback, once }]);
}

export function removeEventListener(name: string, callback: (data: any) => void) {
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
    dispatchTryableEvent(id, "close");
    isClosing = false;
});
var isShowing = false;
addEventListener("mika-try-show", (id) => {
    if (isShowing) return;
    isShowing = true;
    dispatchTryableEvent(id, "show");
    isShowing = false;
});
var isHiding = false;
addEventListener("mika-try-hide", (id) => {
    if (isHiding) return;
    isHiding = true;
    dispatchTryableEvent(id, "hide");
    isHiding = false;
});
