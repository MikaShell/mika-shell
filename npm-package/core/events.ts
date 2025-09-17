import call from "./call";
const listeners: Map<number, Function[]> = new Map();
const onceListeners: Map<number, Function[]> = new Map();
try {
    const ws = new WebSocket(
        `ws://localhost:${globalThis.mikaShell.backendPort}/?type=string&event=${globalThis.mikaShell.id}`
    );
    ws.onmessage = (event_) => {
        const { event, data } = JSON.parse(event_.data);
        dispatch(event, data);
    };
    ws.onclose = () => {
        console.error("Event WebSocket connection closed");
    };
    ws.onerror = (error) => {
        console.error("Event WebSocket error", error);
    };
} catch (error) {
    console.error("Failed to connect to Event WebSocket", error);
}
window.addEventListener("mika-shell-event", (e: any) => {
    const { event, data } = e.detail;
    dispatch(event, data);
});
function subscribe(event: number) {
    return call("mika.subscribe", event);
}
function unsubscribe(event: number) {
    return call("mika.unsubscribe", event);
}
export function on(event: number, callback: Function) {
    if (!listeners.has(event)) {
        listeners.set(event, []);
        subscribe(event);
    }
    listeners.get(event)?.push(callback);
}
export function once(event: number, callback: Function) {
    if (!onceListeners.has(event)) {
        onceListeners.set(event, []);
        subscribe(event);
    }
    onceListeners.get(event)?.push(callback);
}
export function off(event: number, callback: Function) {
    if (listeners.has(event)) {
        const index = listeners.get(event)?.indexOf(callback);
        if (index && index !== -1) {
            listeners.get(event)?.splice(index, 1);
            if (listeners.get(event)?.length === 0) {
                listeners.delete(event);
            }
        }
    }
    if (onceListeners.has(event)) {
        const index = onceListeners.get(event)?.indexOf(callback);
        if (index && index !== -1) {
            onceListeners.get(event)?.splice(index, 1);
            if (onceListeners.get(event)?.length === 0) {
                onceListeners.delete(event);
            }
        }
    }
    if (listeners.get(event) === undefined && onceListeners.get(event) === undefined) {
        unsubscribe(event);
    }
}
function dispatch(event: number, data: any) {
    if (listeners.has(event)) {
        listeners.get(event)?.forEach((callback) => {
            callback(data);
        });
    }
    if (onceListeners.has(event)) {
        onceListeners.get(event)?.forEach((callback) => {
            callback(data);
        });
        onceListeners.delete(event);
    }
}
