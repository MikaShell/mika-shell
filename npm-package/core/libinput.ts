import call from "./call";
import { Emitter } from "./events";
function subscribe(event: string): Promise<void> {
    return call("libinput.subscribe", event);
}
function unsubscribe(event: string): Promise<void> {
    return call("libinput.unsubscribe", event);
}
const emitter = new Emitter("libinput");
emitter.onEmpty = (name: string) => {
    unsubscribe(name);
};
type EventMap = {
    keyboardKey: { key: number; state: number };
    pointerMotion: { x: number; y: number; dx: number; dy: number };
    pointerButton: { button: number; state: number };
};
export type Events = keyof EventMap;
export function on<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    emitter.on(event, callback);
    subscribe(event);
}
export function off<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    emitter.off(event, callback);
    unsubscribe(event);
}
export function once<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    emitter.once(event, callback);
    subscribe(event);
}
