import call from "./call";
import { ForeignToplevel } from "./events-define";
export type State = "maximized" | "minimized" | "activated" | "fullscreen";
export type Client = {
    id: number;
    title: string;
    appId: string;
    state: State[];
};
export function list(): Promise<Client[]> {
    return call("foreignToplevel.list");
}
export function activate(id: number): Promise<void> {
    return call("foreignToplevel.activate", id);
}
export function close(id: number): Promise<void> {
    return call("foreignToplevel.close", id);
}
export function setMaximized(id: number, maximized: boolean): Promise<void> {
    return call("foreignToplevel.setMaximized", id, maximized);
}
export function setMinimized(id: number, minimized: boolean): Promise<void> {
    return call("foreignToplevel.setMinimized", id, minimized);
}
export function setFullscreen(id: number, fullscreen: boolean): Promise<void> {
    return call("foreignToplevel.setFullscreen", id, fullscreen);
}

type Events = keyof typeof ForeignToplevel;
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
    events.on(ForeignToplevel[event], callback);
}
export function off<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.off(ForeignToplevel[event], callback);
}
export function once<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.once(ForeignToplevel[event], callback);
}
