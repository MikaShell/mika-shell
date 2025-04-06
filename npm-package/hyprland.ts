// @ts-ignore
import { Events as wailsEvent } from "@wailsio/runtime";

import * as bindings from "./bindings/github.com/HumXC/mikami/services/index";
import { id, WaitReady } from "./init";
import * as hyprlandEvent from "./bindings/github.com/thiagokokada/hyprland-go/event/models";
export enum EventType {
    Workspace = hyprlandEvent.EventType.EventWorkspace,
    FocusedMonitor = hyprlandEvent.EventType.EventFocusedMonitor,
    ActiveWindow = hyprlandEvent.EventType.EventActiveWindow,
    Fullscreen = hyprlandEvent.EventType.EventFullscreen,
    MonitorRemoved = hyprlandEvent.EventType.EventMonitorRemoved,
    MonitorAdded = hyprlandEvent.EventType.EventMonitorAdded,
    CreateWorkspace = hyprlandEvent.EventType.EventCreateWorkspace,
    DestroyWorkspace = hyprlandEvent.EventType.EventDestroyWorkspace,
    MoveWorkspace = hyprlandEvent.EventType.EventMoveWorkspace,
    ActiveLayout = hyprlandEvent.EventType.EventActiveLayout,
    OpenWindow = hyprlandEvent.EventType.EventOpenWindow,
    CloseWindow = hyprlandEvent.EventType.EventCloseWindow,
    MoveWindow = hyprlandEvent.EventType.EventMoveWindow,
    OpenLayer = hyprlandEvent.EventType.EventOpenLayer,
    CloseLayer = hyprlandEvent.EventType.EventCloseLayer,
    SubMap = hyprlandEvent.EventType.EventSubMap,
    Screencast = hyprlandEvent.EventType.EventScreencast,
}
export namespace Event {
    export type ActiveLayout = hyprlandEvent.ActiveLayout;
    export type ActiveWindow = hyprlandEvent.ActiveWindow;
    export type CloseLayer = hyprlandEvent.CloseLayer;
    export type CloseWindow = hyprlandEvent.CloseWindow;
    export type FocusedMonitor = hyprlandEvent.FocusedMonitor;
    export type Fullscreen = hyprlandEvent.Fullscreen;
    export type MonitorName = hyprlandEvent.MonitorName;
    export type MoveWindow = hyprlandEvent.MoveWindow;
    export type MoveWorkspace = hyprlandEvent.MoveWorkspace;
    export type OpenLayer = hyprlandEvent.OpenLayer;
    export type OpenWindow = hyprlandEvent.OpenWindow;
    export type Screencast = hyprlandEvent.Screencast;
    export type SubMap = hyprlandEvent.SubMap;
    export type WorkspaceName = hyprlandEvent.WorkspaceName;
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
    bindings.Hyprland.Subscribe(id, event as unknown as hyprlandEvent.EventType);
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
    bindings.Hyprland.Unsubscribe(id, event as unknown as hyprlandEvent.EventType);
    if (listeners[event]) {
        const index = listeners[event].indexOf(callback);
        if (index !== -1) listeners[event].splice(index, 1);
    }
}

const ActiveWindow = bindings.Hyprland.ActiveWindow;
const ActiveWorkspace = bindings.Hyprland.ActiveWorkspace;
const Animations = bindings.Hyprland.Animations;
const Binds = bindings.Hyprland.Binds;
const Clients = bindings.Hyprland.Clients;
const ConfigErrors = bindings.Hyprland.ConfigErrors;
const CursorPos = bindings.Hyprland.CursorPos;
const Decorations = bindings.Hyprland.Decorations;
const Devices = bindings.Hyprland.Devices;
const Dispatch = bindings.Hyprland.Dispatch;
const GetOption = bindings.Hyprland.GetOption;
const Keyword = bindings.Hyprland.Keyword;
const Kill = bindings.Hyprland.Kill;
const Layers = bindings.Hyprland.Layers;
const Monitors = bindings.Hyprland.Monitors;
const Reload = bindings.Hyprland.Reload;
const SetCursor = bindings.Hyprland.SetCursor;
const Splash = bindings.Hyprland.Splash;
const SwitchXkbLayout = bindings.Hyprland.SwitchXkbLayout;
const Workspace = bindings.Hyprland.Workspace;

export {
    ActiveWindow,
    ActiveWorkspace,
    Animations,
    Binds,
    Clients,
    ConfigErrors,
    CursorPos,
    Decorations,
    Devices,
    Dispatch,
    GetOption,
    Keyword,
    Kill,
    Layers,
    Monitors,
    Reload,
    SetCursor,
    Splash,
    SwitchXkbLayout,
    Workspace,
};
