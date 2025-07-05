import call from "./call";
export function open(url: string): Promise<void> {
    return call("open", url);
}
export interface WebviewInfo {
    id: number;
    type: "none";
    uri: string;
}
import { addEventListener, removeEventListener } from "./events";

export function addListener(
    name: "open",
    callback: (info: WebviewInfo) => void,
    once: boolean = false
) {
    addEventListener(`mika-${name}`, callback, once);
}

export function removeListener(name: "open", callback: (info: WebviewInfo) => void) {
    removeEventListener(`mika-${name}`, callback);
}
