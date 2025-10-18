import call from "./call";
import { PolkitAgent } from "./events-define";

export type Context = {
    actionId: string;
    message: string;
    iconName: string;
    details: any;
    cookie: string;
    // { unixUser: uid } or { unixGroup: gid }
    identities: { [key: string]: number }[];
};
export function auth(
    cookie: string,
    username: string,
    password: string
): Promise<{ ok: boolean; err: string | null }> {
    return call("polkitAgent.auth", cookie, username, password);
}
export function cancel(cookie: string): Promise<void> {
    return call("polkitAgent.cancel", cookie);
}
type Events = keyof typeof PolkitAgent;
type EventMap = {
    [K in Events]: K extends "cancel" ? (cookie: string) => void : never;
};
import * as events from "./events";
export function on<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.on(PolkitAgent[event], callback);
}
export function off<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.off(PolkitAgent[event], callback);
}
export function once<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.once(PolkitAgent[event], callback);
}
