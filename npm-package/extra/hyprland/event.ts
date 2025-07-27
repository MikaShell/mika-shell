import { getSocket } from "./common";
var socket: WebSocket | boolean = false;
async function setupSocket() {
    if (socket) return;
    socket = true;
    socket = await getSocket("event");
    socket.onerror = (event) => {
        console.error("Hyprland event socket error:", event);
    };
    let buffer = "";
    socket.onmessage = (event) => {
        buffer += event.data;
        const parts = buffer.split("\n");
        // 如果不是以 \n 结尾，最后一部分是残缺的，作为新的 buffer
        buffer = buffer.endsWith("\n") ? "" : parts.pop() || "";
        for (const message of parts) {
            if (!message) continue;
            if (message.length === 0) continue;
            try {
                const { name, args } = parseMessage(message);
                const data = makeData(name, args);
                dispatchEvent(name, data);
            } catch (err) {
                console.error("Failed to handle message:", message, err);
            }
        }
    };
}
function makeData(name: string, args: string[]): any {
    switch (name) {
        case "workspace":
            return { workspaceName: args[0] };
        case "workspacev2":
            return { workspaceId: parseInt(args[0]), workspaceName: args[1] };
        case "focusedmon":
            return { monitorName: args[0], workspaceName: args[1] };
        case "focusedmonv2":
            return { monitorName: args[0], workspaceId: parseInt(args[1]) };
        case "activewindow":
            return { windowClass: args[0], windowTitle: args[1] };
        case "activewindowv2":
            return { windowAddress: args[0] };
        case "fullscreen":
            return { state: args[0] === "1" ? "enter" : "exit" };
        case "monitorremoved":
            return { monitorName: args[0] };
        case "monitorremovedv2":
            return {
                monitorId: parseInt(args[0]),
                monitorName: args[1],
                monitorDescription: args[2],
            };
        case "monitoradded":
            return { monitorName: args[0] };
        case "monitoraddedv2":
            return {
                monitorId: parseInt(args[0]),
                monitorName: args[1],
                monitorDescription: args[2],
            };
        case "createworkspace":
            return { workspaceName: args[0] };
        case "createworkspacev2":
            return { workspaceId: parseInt(args[0]), workspaceName: args[1] };
        case "destroyworkspace":
            return { workspaceName: args[0] };
        case "destroyworkspacev2":
            return { workspaceId: parseInt(args[0]), workspaceName: args[1] };
        case "moveworkspace":
            return { workspaceName: args[0], monitorName: args[1] };
        case "moveworkspacev2":
            return { workspaceId: parseInt(args[0]), workspaceName: args[1], monitorName: args[2] };
        case "renameworkspace":
            return { workspaceId: parseInt(args[0]), newName: args[1] };
        case "activespecial":
            return { workspaceName: args[0], monitorName: args[1] };
        case "activespecialv2":
            return { workspaceId: parseInt(args[0]), workspaceName: args[1], monitorName: args[2] };
        case "activelayout":
            return { keyboardName: args[0], layoutName: args[1] };
        case "openwindow":
            return {
                windowAddress: args[0],
                workspaceName: args[1],
                windowClass: args[2],
                windowTitle: args[3],
            };
        case "closewindow":
            return { windowAddress: args[0] };
        case "movewindow":
            return { windowAddress: args[0], workspaceName: args[1] };
        case "movewindowv2":
            return {
                windowAddress: args[0],
                workspaceId: parseInt(args[1]),
                workspaceName: args[2],
            };
        case "openlayer":
            return { namespace: args[0] };
        case "closelayer":
            return { namespace: args[0] };
        case "submap":
            return { submapName: args[0] };
        case "changefloatingmode":
            return { windowAddress: args[0], floating: args[1] === "1" };
        case "urgent":
            return { windowAddress: args[0] };
        case "screencast":
            return {
                state: args[0] === "1",
                owner: args[1] === "1" ? "monitor-share" : "window-share",
            };
        case "windowtitle":
            return { windowAddress: args[0] };
        case "windowtitlev2":
            return { windowAddress: args[0], windowTitle: args[1] };
        case "togglegroup":
            return { destroyed: args[0] === "1", windowAddresses: args.slice(1) };
        case "moveintogroup":
            return { windowAddress: args[0] };
        case "moveoutofgroup":
            return { windowAddress: args[0] };
        case "ignoregrouplock":
            return { state: args[0] === "1" };
        case "lockgroups":
            return { state: args[0] === "1" };
        case "configreloaded":
            return null;
        case "pin":
            return { windowAddress: args[0], state: args[1] === "1" };
        case "minimized":
            return { windowAddress: args[0], state: args[1] === "1" };
        case "bell":
            return { windowAddress: args[0] || null };
        default:
            return null;
    }
}
function parseMessage(message: string) {
    const parts = message.split(">>");
    const name = parts.shift() as string;
    const args = (parts.shift() || "").split(",");
    return { name, args };
}
type EventMap = {
    workspace: {
        workspaceName: string;
    };
    workspacev2: {
        workspaceId: number;
        workspaceName: string;
    };
    focusedmon: {
        monitorName: string;
        workspaceName: string;
    };
    focusedmonv2: {
        monitorName: string;
        workspaceId: number;
    };
    activewindow: {
        windowClass: string;
        windowTitle: string;
    };
    activewindowv2: {
        windowAddress: string;
    };
    fullscreen: {
        state: "exit" | "enter"; // 0 - exit, 1 - enter
    };
    monitorremoved: {
        monitorName: string;
    };
    monitorremovedv2: {
        monitorId: number;
        monitorName: string;
        monitorDescription: string;
    };
    monitoradded: {
        monitorName: string;
    };
    monitoraddedv2: {
        monitorId: number;
        monitorName: string;
        monitorDescription: string;
    };
    createworkspace: {
        workspaceName: string;
    };
    createworkspacev2: {
        workspaceId: number;
        workspaceName: string;
    };
    destroyworkspace: {
        workspaceName: string;
    };
    destroyworkspacev2: {
        workspaceId: number;
        workspaceName: string;
    };
    moveworkspace: {
        workspaceName: string;
        monitorName: string;
    };
    moveworkspacev2: {
        workspaceId: number;
        workspaceName: string;
        monitorName: string;
    };
    renameworkspace: {
        workspaceId: string;
        newName: string;
    };
    activespecial: {
        workspaceName: string;
        monitorName: string;
    };
    activespecialv2: {
        workspaceId: string;
        workspaceName: string;
        monitorName: string;
    };
    activelayout: {
        keyboardName: string;
        layoutName: string;
    };
    openwindow: {
        windowAddress: string;
        workspaceName: string;
        windowClass: string;
        windowTitle: string;
    };
    closewindow: {
        windowAddress: string;
    };
    movewindow: {
        windowAddress: string;
        workspaceName: string;
    };
    movewindowv2: {
        windowAddress: string;
        workspaceId: string;
        workspaceName: string;
    };
    openlayer: {
        namespace: string;
    };
    closelayer: {
        namespace: string;
    };
    submap: {
        submapName: string;
    };
    changefloatingmode: {
        windowAddress: string;
        floating: boolean;
    };
    urgent: {
        windowAddress: string;
    };
    screencast: {
        state: boolean;
        owner: "monitor-share" | "window-share"; // 0 - monitor share, 1 - window share
    };
    windowtitle: {
        windowAddress: string;
    };
    windowtitlev2: {
        windowAddress: string;
        windowTitle: string;
    };
    togglegroup: {
        destroyed: boolean;
        windowAddresses: string[];
    };
    moveintogroup: {
        windowAddress: string;
    };
    moveoutofgroup: {
        windowAddress: string;
    };
    ignoregrouplock: {
        state: boolean;
    };
    lockgroups: {
        state: boolean;
    };
    configreloaded: null;
    pin: {
        windowAddress: string;
        state: boolean;
    };
    minimized: {
        windowAddress: string;
        state: boolean;
    };
    bell: {
        windowAddress: string | null;
    };
};

const listeners: Map<string, Array<(data: EventMap[keyof EventMap]) => void>> = new Map();
const onceListeners: Map<string, Array<(data: EventMap[keyof EventMap]) => void>> = new Map();
function dispatchEvent(event: string, data: any) {
    const callbacks = listeners.get(event) || [];
    for (const callback of callbacks) {
        callback(data);
    }
    const once = onceListeners.get(event);
    if (once) {
        for (const callback of once) {
            callback(data);
        }
        onceListeners.delete(event);
    }
}
export function on<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    setupSocket();
    if (!listeners.has(event)) {
        listeners.set(event, []);
    }
    listeners.get(event)!.push(callback as any);
}
export function once<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    setupSocket();
    if (!onceListeners.has(event)) {
        onceListeners.set(event, []);
    }
    onceListeners.get(event)!.push(callback as any);
}
export function off<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    const callbacks = listeners.get(event) || [];
    var index = callbacks.indexOf(callback as any);
    if (index !== -1) {
        callbacks.splice(index, 1);
    }
    const onceCallback = onceListeners.get(event) || [];
    index = onceCallback.indexOf(callback as any);
    if (index !== -1) {
        onceCallback.splice(index, 1);
    }
}
