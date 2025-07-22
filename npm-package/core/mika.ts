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
import { Emitter } from "./events";

type EventMap = {
    open: WebviewInfo;
    close: number;
};
const emitter = new Emitter("mika");
export function on<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    emitter.on(event, callback);
}
export function off<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    emitter.off(event, callback);
}
export function once<K extends keyof EventMap>(event: K, callback: (data: EventMap[K]) => void) {
    emitter.once(event, callback);
}
