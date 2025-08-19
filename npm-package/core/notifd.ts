export interface Notification {
    id: number;
    appName: string;
    replacesId: number;
    appIcon: string;
    summary: string;
    body: string;
    actions: string[];
    hints: {
        actionIcons?: boolean;
        category?: string;
        desktopEntry?: string;
        imageData?: {
            width: number;
            height: number;
            rowstride: number;
            hasAlpha: boolean;
            bitsPerSample: number;
            channels: number;
            base64: string;
        };
        imagePath?: string;
        resident?: boolean;
        soundFile?: string;
        soundName?: string;
        suppressSound?: boolean;
        transient?: boolean;
        x?: number;
        y?: number;
        urgency?: "low" | "normal" | "critical";
        senderPID?: number;
    };
    expireTimeout: number;
    timestamp: number;
}
function convert(n: any) {
    var hints: any[] = n.hints;
    n.hints = {};
    hints.forEach((hint) => {
        if (hint["actionIcons"]) {
            n.hints.imageData = hint["actionIcons"];
        } else if (hint["category"]) {
            n.hints.category = hint["category"];
        } else if (hint["desktopEntry"]) {
            n.hints.desktopEntry = hint["desktopEntry"];
        } else if (hint["imageData"]) {
            n.hints.imageData = hint["imageData"];
        } else if (hint["imagePath"]) {
            n.hints.imagePath = hint["imagePath"];
        } else if (hint["resident"]) {
            n.hints.resident = hint["resident"];
        } else if (hint["soundFile"]) {
            n.hints.soundFile = hint["soundFile"];
        } else if (hint["soundName"]) {
            n.hints.soundName = hint["soundName"];
        } else if (hint["suppressSound"]) {
            n.hints.suppressSound = hint["suppressSound"];
        } else if (hint["transient"]) {
            n.hints.transient = hint["transient"];
        } else if (hint["x"]) {
            n.hints.x = hint["x"];
        } else if (hint["y"]) {
            n.hints.y = hint["y"];
        } else if (hint["urgency"]) {
            n.hints.urgency = hint["urgency"];
        } else if (hint["senderPID"]) {
            n.hints.senderPID = hint["senderPID"];
        }
    });
}
import call from "./call";
export async function get(id: number): Promise<Notification> {
    const n = await call("notifd.get", id);
    convert(n);
    return n;
}
export async function getAll(): Promise<Notification[]> {
    const ns = await call("notifd.getAll");
    ns.forEach((n: any) => convert(n));
    return ns;
}
export function dismiss(id: number): Promise<void> {
    return call("notifd.dismiss", id);
}
export function activate(id: number, action: string = "default"): Promise<void> {
    return call("notifd.activate", id, action);
}
export function setDontDisturb(value: boolean): Promise<void> {
    return call("notifd.setDontDisturb", value);
}
import { Notifd } from "./events-define";
import * as events from "./events";
type Events = keyof typeof Notifd;
export function on<K extends Events>(event: K, callback: (id: number) => void) {
    events.on(Notifd[event], callback);
}
export function off<K extends Events>(event: K, callback: (id: number) => void) {
    events.off(Notifd[event], callback);
}
export function once<K extends Events>(event: K, callback: (id: number) => void) {
    events.once(Notifd[event], callback);
}
