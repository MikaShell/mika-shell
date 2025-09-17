import { getSocket } from "./common";

export async function send(message: string, json: boolean = true): Promise<string | null> {
    const socket = await getSocket("command");
    return new Promise((resolve, reject) => {
        let buffer = "";
        socket.onopen = () => {
            socket.send((json ? "[j]/" : "") + message);
        };
        socket.onmessage = (event) => {
            buffer += event.data;
        };
        socket.onclose = () => {
            if (buffer.length > 0) resolve(buffer);
            else resolve(null);
        };
        socket.onerror = () => {
            reject(new Error("WebSocket error"));
        };
    });
}
async function sendAndParseMessage<T extends any>(message: string): Promise<T | null> {
    const result = await send(message);
    if (result === null) return null;
    return JSON.parse(result) as T;
}
import {
    Bezier,
    Window,
    Workspace,
    Animation,
    Bind,
    Client,
    Decoration,
    Devices,
    Layers,
    Monitor,
    Version,
} from "./types";
export function activewindow() {
    return sendAndParseMessage<Window>("activewindow");
}

export function activeworkspace() {
    return sendAndParseMessage<Workspace>("activeworkspace");
}

export function animations() {
    return sendAndParseMessage<[Animation[], Bezier[]]>("animations");
}
export function binds() {
    return sendAndParseMessage<Bind[]>("binds");
}

export function clients() {
    return sendAndParseMessage<Client[]>("clients");
}

export function configerrors() {
    return sendAndParseMessage<string[]>("configerrors");
}
export function cursorpos() {
    return sendAndParseMessage<{ x: number; y: number }>("cursorpos");
}

export function decorations(title?: string, class_?: string) {
    const args: string[] = [];
    if (title) args.push(`title:${title}`);
    if (class_) args.push(`class:\"${class_}`);
    return sendAndParseMessage<Decoration[]>("decorations " + args.join(","));
}
export function devices() {
    return sendAndParseMessage<Devices>("devices");
}
export async function dismissnotify(amount: string): Promise<void> {
    await send(`dismissnotify ${amount}`);
}
export async function dispatch(dispatcher: string, ...args: string[]): Promise<void> {
    await send(`dispatch ${dispatcher} ${args.join(" ")}`);
}
export async function getoption(option: string) {
    return send(`getoption ${option}`);
}
export function groups() {
    return sendAndParseMessage<unknown[]>("groups");
}
export function hyprpaper(...args: string[]) {
    return sendAndParseMessage<unknown>("hyprpaper " + args.join(" "));
}
export function hyprsunset(...args: string[]) {
    return sendAndParseMessage<unknown>("hyprsunset " + args.join(" "));
}
export async function keybind(name: string, value: string): Promise<void> {
    await send(`keybind ${name} ${value}`);
}
export async function kill(): Promise<void> {
    await send(`kill`);
}
export async function layers() {
    return sendAndParseMessage<Layers>("layers");
}
export async function layouts() {
    return sendAndParseMessage<string[]>("layouts");
}
export function monitors() {
    return sendAndParseMessage<Monitor[]>("monitors");
}
export async function notify(...args: string[]): Promise<void> {
    await send(`notify ${args.join(" ")}`);
}
export async function output(...args: string[]): Promise<void> {
    await send(`output ${args.join(" ")}`);
}
export async function plugin(...args: string[]): Promise<void> {
    await send(`plugin ${args.join(" ")}`);
}
export async function reload(configOnly: boolean = false): Promise<void> {
    await send(`reload ${configOnly ? "config-only" : ""}`);
}
export function rollinglog(): Promise<string | null> {
    return send(`rollinglog`, false);
}
export async function setcursor(theme: string, size: number): Promise<void> {
    await send(`setcursor ${theme} ${size}`);
}
export async function seterror(color: string, ...message: string[]): Promise<void> {
    await send(`seterror ${color} ${message.join(" ")}`);
}
type Prop =
    | "activebordercolor"
    | "alpha"
    | "alphafullscreen"
    | "alphafullscreenoverride"
    | "alphainactive"
    | "alphainactiveoverride"
    | "alphaoverride"
    | "animationstyle"
    | "bordersize"
    | "dimaround"
    | "forceallowsinput"
    | "forcenoborder"
    | "forcenodim"
    | "forcenoshadow"
    | "forceopaque"
    | "forceopaqueoverride"
    | "inactivebordercolor"
    | "keepaspectratio"
    | "maxsize"
    | "minsize"
    | "nofocus"
    | "nomaxsize"
    | "rounding"
    | "windowdancecompat";
export async function setprop(prop: Prop, value: string): Promise<void> {
    await send(`setprop ${prop} ${value}`);
}
export function splash(): Promise<string | null> {
    return send(`splash`, false);
}
export async function switchxkblayout(...args: string[]): Promise<void> {
    await send(`switchxkblayout ${args.join(" ")}`);
}
export function systeminfo(): Promise<string | null> {
    return send(`systeminfo`, false);
}
export function version() {
    return sendAndParseMessage<Version>("version");
}
export function workspacerules() {
    return sendAndParseMessage<unknown[]>("workspacerules");
}
export function workspaces() {
    return sendAndParseMessage<Workspace[]>("workspaces");
}
