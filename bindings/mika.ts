import call from "./call";
export function open(name: string): Promise<void> {
    return call("mika.open", name);
}
export function close(id: number): Promise<void> {
    return call("mika.close", id);
}
export interface WebviewInfo {
    id: number;
    type: "none";
    uri: string;
}
import { addEventListener, removeEventListener } from "./events";

type EventMap = {
    open: WebviewInfo;
    close: number;
};

export function on<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    addEventListener(`mika-${event}`, callback);
}
export function off<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    removeEventListener(`mika-${event}`, callback);
}
export function once<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    addEventListener(`mika-${event}`, callback, true);
}
