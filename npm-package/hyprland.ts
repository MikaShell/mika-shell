import * as hyprland from "./bindings/github.com/HumXC/mikami/services/hyprland";
import { id, WailsEventOff, WailsEventOn, WaitReady } from "./common";
import * as hyprlandEventModels from "./bindings/github.com/thiagokokada/hyprland-go/event/models";
export type EventType =
    | "workspace"
    | "focused-monitor"
    | "active-window"
    | "fullscreen"
    | "monitor-removed"
    | "monitor-added"
    | "create-workspace"
    | "destroy-workspace"
    | "move-workspace"
    | "active-layout"
    | "open-window"
    | "close-window"
    | "move-window"
    | "open-layer"
    | "close-layer"
    | "sub-map"
    | "screencast";

// Workspace = hyprlandEventModels.EventType.EventWorkspace,
// FocusedMonitor = hyprlandEventModels.EventType.EventFocusedMonitor,
// ActiveWindow = hyprlandEventModels.EventType.EventActiveWindow,
// Fullscreen = hyprlandEventModels.EventType.EventFullscreen,
// MonitorRemoved = hyprlandEventModels.EventType.EventMonitorRemoved,
// MonitorAdded = hyprlandEventModels.EventType.EventMonitorAdded,
// CreateWorkspace = hyprlandEventModels.EventType.EventCreateWorkspace,
// DestroyWorkspace = hyprlandEventModels.EventType.EventDestroyWorkspace,
// MoveWorkspace = hyprlandEventModels.EventType.EventMoveWorkspace,
// ActiveLayout = hyprlandEventModels.EventType.EventActiveLayout,
// OpenWindow = hyprlandEventModels.EventType.EventOpenWindow,
// CloseWindow = hyprlandEventModels.EventType.EventCloseWindow,
// MoveWindow = hyprlandEventModels.EventType.EventMoveWindow,
// OpenLayer = hyprlandEventModels.EventType.EventOpenLayer,
// CloseLayer = hyprlandEventModels.EventType.EventCloseLayer,
// SubMap = hyprlandEventModels.EventType.EventSubMap,
// Screencast = hyprlandEventModels.EventType.EventScreencast,
export namespace Event {
    export type ActiveLayout = hyprlandEventModels.ActiveLayout;
    export type ActiveWindow = hyprlandEventModels.ActiveWindow;
    export type CloseLayer = hyprlandEventModels.CloseLayer;
    export type CloseWindow = hyprlandEventModels.CloseWindow;
    export type FocusedMonitor = hyprlandEventModels.FocusedMonitor;
    export type Fullscreen = hyprlandEventModels.Fullscreen;
    export type MonitorName = hyprlandEventModels.MonitorName;
    export type MoveWindow = hyprlandEventModels.MoveWindow;
    export type MoveWorkspace = hyprlandEventModels.MoveWorkspace;
    export type OpenLayer = hyprlandEventModels.OpenLayer;
    export type OpenWindow = hyprlandEventModels.OpenWindow;
    export type Screencast = hyprlandEventModels.Screencast;
    export type SubMap = hyprlandEventModels.SubMap;
    export type WorkspaceName = hyprlandEventModels.WorkspaceName;
}
type TypeMap = {
    ["workspace"]: Event.WorkspaceName;
    ["focused-monitor"]: Event.FocusedMonitor;
    ["active-window"]: Event.ActiveWindow;
    ["fullscreen"]: Event.Fullscreen;
    ["monitor-removed"]: Event.MonitorName;
    ["monitor-added"]: Event.MonitorName;
    ["create-workspace"]: Event.WorkspaceName;
    ["destroy-workspace"]: Event.WorkspaceName;
    ["move-workspace"]: Event.MoveWorkspace;
    ["active-layout"]: Event.ActiveLayout;
    ["open-window"]: Event.OpenWindow;
    ["close-window"]: Event.CloseWindow;
    ["move-window"]: Event.MoveWindow;
    ["open-layer"]: Event.OpenLayer;
    ["close-layer"]: Event.CloseLayer;
    ["sub-map"]: Event.SubMap;
    ["screencast"]: Event.Screencast;
};
const listeners: { [key in EventType]?: Function[] } = {};
export async function Subscribe<T extends EventType>(
    event: T,
    callback: (data: TypeMap[T]) => void
) {
    if (id === 0) await WaitReady();
    if (!listeners[event]) listeners[event] = [];
    if (listeners[event].length === 0) {
        hyprland.Subscribe(id, event as unknown as hyprlandEventModels.EventType);
        WailsEventOn(`Hyprland.${event.replace("-", "")}`, (e) => {
            const data = e.data[0];
            for (const listener of listeners[event] || []) {
                listener(data as TypeMap[T]);
            }
        });
    }
    listeners[event].push(callback);
}

export async function Unsubscribe<T extends EventType>(
    event: T,
    callback: (data: TypeMap[T]) => void
) {
    if (id === 0) await WaitReady();
    if (listeners[event]) {
        const index = listeners[event].indexOf(callback);
        if (index !== -1) listeners[event].splice(index, 1);
        if (listeners[event].length === 0) {
            hyprland.Unsubscribe(id, event as unknown as hyprlandEventModels.EventType);
            WailsEventOff(`Hyprland.${event.replace("-", "")}`);
        }
    }
}

export {
    ActiveWindow as GetActiveWindow,
    ActiveWorkspace as GetActiveWorkspace,
    Animations as GetAnimations,
    Binds as GetBinds,
    Clients as GetClients,
    ConfigErrors as GetConfigErrors,
    CursorPos as GetCursorPos,
    Decorations as GetDecorations,
    Devices as GetDevices,
    GetOption as GetOption,
    Layers as GetLayers,
    Monitors as GetMonitors,
    Reload as GetReload,
    Splash as GetSplash,
    Workspace as GetWorkspace,
    Dispatch,
    Kill,
    Keyword,
    SetCursor,
    SwitchXkbLayout,
} from "./bindings/github.com/HumXC/mikami/services/hyprland";

export {
    Window,
    Workspace,
    Animation,
    Bind,
    ConfigError,
    CursorPos,
    Decoration,
    Devices,
    Response,
    Option,
    Layer,
    Monitor,
} from "./bindings/github.com/thiagokokada/hyprland-go/models";
