import call from "./call";
import { Emitter } from "./events";
export type State = "maximized" | "minimized" | "activated" | "fullscreen";
export type Item = {
    id: number;
    title: string;
    appId: string;
    state: State[];
};
export function subscribe(): Promise<void> {
    return call("dock.subscribe");
}
export function unsubscribe(): Promise<void> {
    return call("dock.unsubscribe");
}
export function list(): Promise<Item[]> {
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
const emitter = new Emitter("dock");
emitter.init = subscribe;
emitter.deinit = unsubscribe;

type EventMap = {
    added: (item: Item) => void;
    changed: (item: Item) => void;
    closed: (id: number) => void;
    enter: (id: number) => void;
    leave: (id: number) => void;
    activated: (id: number) => void;
};
export type Events = keyof EventMap;
export function on<K extends Events>(event: K, callback: EventMap[K]) {
    emitter.on(event, callback);
}
export function off<K extends Events>(event: K, callback: EventMap[K]) {
    emitter.off(event, callback);
}
export function once<K extends Events>(event: K, callback: EventMap[K]) {
    emitter.once(event, callback);
}
