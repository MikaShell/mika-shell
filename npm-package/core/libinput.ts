import * as events from "./events";
import { Libinput } from "./events-define";

type Events = keyof typeof Libinput;
type EventMap = {
    [K in Events]: K extends "pointer-motion"
        ? { x: number; y: number; dx: number; dy: number }
        : K extends "pointer-button"
        ? { button: number; state: number }
        : K extends "keyboard-key"
        ? { key: number; state: number }
        : never;
};

export function on<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.on(Libinput[event], callback);
}
export function off<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.off(Libinput[event], callback);
}
export function once<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.once(Libinput[event], callback);
}
