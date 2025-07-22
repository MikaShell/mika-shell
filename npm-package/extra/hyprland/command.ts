import { getSocket } from "./common";

export async function send(message: string, json: boolean = true): Promise<string | null> {
    const socket = await getSocket("command");
    return new Promise((resolve, reject) => {
        var buffer = "";
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
        socket.onerror = (error) => {
            reject(error);
        };
    });
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
export async function activewindow(): Promise<Window> {
    return JSON.parse((await send("activewindow")) as string) as Window;
}

export async function activeworkspace(): Promise<Workspace> {
    return JSON.parse((await send("activeworkspace")) as string) as Workspace;
}

export async function animations(): Promise<[Animation[], Bezier[]]> {
    return JSON.parse((await send("animations")) as string) as [Animation[], Bezier[]];
}
export async function binds(): Promise<Bind[]> {
    return JSON.parse((await send("binds")) as string) as Bind[];
}

export async function clients(): Promise<Client[]> {
    return JSON.parse((await send("clients")) as string) as Client[];
}

export async function configerrors(): Promise<string[]> {
    return (JSON.parse((await send("configerrors")) as string) as string[]).filter(
        (x) => x.length > 0
    );
}
export async function cursorpos(): Promise<{ x: number; y: number }> {
    return JSON.parse((await send("cursorpos")) as string) as { x: number; y: number };
}

export async function decorations(title?: string, class_?: string): Promise<Decoration[]> {
    const args: string[] = [];
    if (title) args.push(`title:${title}`);
    if (class_) args.push(`class:\"${class_}`);
    const result = JSON.parse((await send("decorations " + args.join(","))) as string);
    if (result === "none") return [];
    return result as Decoration[];
}
export async function devices(): Promise<Devices> {
    return JSON.parse((await send("devices")) as string) as Devices;
}
export async function dismissnotify(amount: string): Promise<void> {
    await send(`dismissnotify ${amount}`);
}
export async function dispatch(dispatcher: string, ...args: string[]): Promise<void> {
    await send(`dispatch ${dispatcher} ${args.join(" ")}`);
}
export async function getoption(option: string): Promise<string> {
    return (await send(`getoption ${option}`)) as string;
}
export async function groups(): Promise<unknown[]> {
    return JSON.parse((await send("groups")) as string) as unknown[];
}
export async function hyprpaper(...args: string[]): Promise<unknown> {
    return JSON.parse((await send(`hyprpaper ${args.join(" ")}`)) as string) as unknown;
}
export async function hyprsunset(...args: string[]): Promise<unknown> {
    return JSON.parse((await send(`hyprsunset ${args.join(" ")}`)) as string) as unknown;
}
export async function keybind(name: string, value: string): Promise<void> {
    await send(`keybind ${name} ${value}`);
}
export async function kill(): Promise<void> {
    await send(`kill`);
}
export async function layers(): Promise<Layers> {
    return JSON.parse((await send("layers")) as string) as Layers;
}
export async function layouts(): Promise<string[]> {
    return JSON.parse((await send("layouts")) as string) as string[];
}
export async function monitors(): Promise<Monitor[]> {
    return JSON.parse((await send("monitors")) as string) as Monitor[];
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
export async function rollinglog(): Promise<string> {
    return (await send(`rollinglog`, false)) as string;
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
export async function splash(): Promise<string> {
    return (await send(`splash`, false)) as string;
}
export async function switchxkblayout(...args: string[]): Promise<void> {
    await send(`switchxkblayout ${args.join(" ")}`);
}
export async function systeminfo(): Promise<string> {
    return (await send(`systeminfo`, false)) as string;
}
export async function version(): Promise<Version> {
    return JSON.parse((await send(`version`)) as string) as Version;
}
export async function workspacerules(): Promise<unknown[]> {
    return JSON.parse((await send(`workspacerules`)) as string) as unknown[];
}
export async function workspaces(): Promise<Workspace[]> {
    return JSON.parse((await send(`workspaces`)) as string) as Workspace[];
}
