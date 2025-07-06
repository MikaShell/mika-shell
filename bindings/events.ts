interface Listener {
    callback: (data: any) => void;
    once: boolean;
}
const listeners: Map<string, Listener[]> = new Map();

export function addEventListener(
    name: string,
    callback: (data: any) => void,
    once: boolean = false
) {
    listeners.set(name, [...(listeners.get(name) || []), { callback, once }]);
    window.addEventListener("mika-shell-event", (event: any) => {
        const name: string = event.detail.name;
        const data: any = event.detail.data;
        const callbacks = listeners.get(name) || [];
        callbacks.forEach((listener) => {
            if (listener.once) {
                removeEventListener(name, listener.callback);
            }
            listener.callback(data);
        });
    });
}

export function removeEventListener(name: string, callback: (data: any) => void) {
    const callbacks = listeners.get(name) || [];
    const index = callbacks.findIndex((listener) => listener.callback === callback);
    if (index >= 0) {
        callbacks.splice(index, 1);
        listeners.set(name, callbacks);
    }
}
