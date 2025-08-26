import call from "./call";
import { Dock } from "./events-define";
export type State = "maximized" | "minimized" | "activated" | "fullscreen";
export type Client = {
    id: number;
    title: string;
    appId: string;
    state: State[];
};
export function list(): Promise<Client[]> {
    return call("dock.list");
}
export function activate(id: number): Promise<void> {
    return call("dock.activate", id);
}
export function close(id: number): Promise<void> {
    return call("dock.close", id);
}
export function setMaximized(id: number, maximized: boolean): Promise<void> {
    return call("dock.setMaximized", id, maximized);
}
export function setMinimized(id: number, minimized: boolean): Promise<void> {
    return call("dock.setMinimized", id, minimized);
}
export function setFullscreen(id: number, fullscreen: boolean): Promise<void> {
    return call("dock.setFullscreen", id, fullscreen);
}

type Events = keyof typeof Dock;
type EventMap = {
    [K in Events]: K extends "changed"
        ? (item: Client) => void
        : K extends "closed"
        ? (id: number) => void
        : K extends "enter"
        ? (id: number) => void
        : K extends "leave"
        ? (id: number) => void
        : K extends "activated"
        ? (id: number) => void
        : never;
};
import * as events from "./events";
export function on<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.on(Dock[event], callback);
}
export function off<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.off(Dock[event], callback);
}
export function once<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.once(Dock[event], callback);
}
