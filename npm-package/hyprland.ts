// @ts-ignore
import { Events as wailsEvent } from "@wailsio/runtime";

import * as hyprland from "./bindings/github.com/HumXC/mikami/services/hyprland";
import { id, WaitReady } from "./init";
import * as hyprlandEventModels from "./bindings/github.com/thiagokokada/hyprland-go/event/models";
export enum EventType {
    Workspace = hyprlandEventModels.EventType.EventWorkspace,
    FocusedMonitor = hyprlandEventModels.EventType.EventFocusedMonitor,
    ActiveWindow = hyprlandEventModels.EventType.EventActiveWindow,
    Fullscreen = hyprlandEventModels.EventType.EventFullscreen,
    MonitorRemoved = hyprlandEventModels.EventType.EventMonitorRemoved,
    MonitorAdded = hyprlandEventModels.EventType.EventMonitorAdded,
    CreateWorkspace = hyprlandEventModels.EventType.EventCreateWorkspace,
    DestroyWorkspace = hyprlandEventModels.EventType.EventDestroyWorkspace,
    MoveWorkspace = hyprlandEventModels.EventType.EventMoveWorkspace,
    ActiveLayout = hyprlandEventModels.EventType.EventActiveLayout,
    OpenWindow = hyprlandEventModels.EventType.EventOpenWindow,
    CloseWindow = hyprlandEventModels.EventType.EventCloseWindow,
    MoveWindow = hyprlandEventModels.EventType.EventMoveWindow,
    OpenLayer = hyprlandEventModels.EventType.EventOpenLayer,
    CloseLayer = hyprlandEventModels.EventType.EventCloseLayer,
    SubMap = hyprlandEventModels.EventType.EventSubMap,
    Screencast = hyprlandEventModels.EventType.EventScreencast,
}
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
    [EventType.Workspace]: Event.WorkspaceName;
    [EventType.FocusedMonitor]: Event.FocusedMonitor;
    [EventType.ActiveWindow]: Event.ActiveWindow;
    [EventType.Fullscreen]: Event.Fullscreen;
    [EventType.MonitorRemoved]: Event.MonitorName;
    [EventType.MonitorAdded]: Event.MonitorName;
    [EventType.CreateWorkspace]: Event.WorkspaceName;
    [EventType.DestroyWorkspace]: Event.WorkspaceName;
    [EventType.MoveWorkspace]: Event.MoveWorkspace;
    [EventType.ActiveLayout]: Event.ActiveLayout;
    [EventType.OpenWindow]: Event.OpenWindow;
    [EventType.CloseWindow]: Event.CloseWindow;
    [EventType.MoveWindow]: Event.MoveWindow;
    [EventType.OpenLayer]: Event.OpenLayer;
    [EventType.CloseLayer]: Event.CloseLayer;
    [EventType.SubMap]: Event.SubMap;
    [EventType.Screencast]: Event.Screencast;
};
const listeners: { [key in EventType]?: Function[] } = {};
export async function Subscribe<T extends EventType>(
    event: T,
    callback: (data: TypeMap[T]) => void
) {
    if (id === 0) await WaitReady();
    hyprland.Subscribe(id, event as unknown as hyprlandEventModels.EventType);
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(callback);
    wailsEvent.On(`Hyprland.${event}`, (ev: any) => {
        const data = ev.data[0];
        for (const listener of listeners[event] || []) {
            listener(data as TypeMap[T]);
        }
    });
}

export async function Unsubscribe<T extends EventType>(
    event: T,
    callback: (data: TypeMap[T]) => void
) {
    if (id === 0) await WaitReady();
    hyprland.Unsubscribe(id, event as unknown as hyprlandEventModels.EventType);
    if (listeners[event]) {
        const index = listeners[event].indexOf(callback);
        if (index !== -1) listeners[event].splice(index, 1);
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
