interface Notification {
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
            webp: string;
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
export function subscribe(): Promise<void> {
    return call("notifd.subscribe");
}
export function unsubscribe(): Promise<void> {
    return call("notifd.unsubscribe");
}
export function activate(id: number, action: string = "default"): Promise<void> {
    return call("notifd.activate", id, action);
}
export function setDontDisturb(value: boolean): Promise<void> {
    return call("notifd.setDontDisturb", value);
}
type Events = "added" | "removed";
import { Emitter } from "./events";

const emitter = new Emitter("notifd");
emitter.init = subscribe;
emitter.deinit = unsubscribe;
export function on(event: Events, callback: (id: number) => void) {
    emitter.on(event, callback);
}
export function off(event: Events, callback: (id: number) => void) {
    emitter.off(event, callback);
}
export function once(event: Events, callback: (id: number) => void) {
    emitter.once(event, callback);
}
const proxied: Array<Notification[]> = [];
const onAdded = async (id: number) => {
    const item = await get(id);
    if (item.replacesId === 0) {
        for (const p of proxied) {
            p.push(item);
        }
    } else {
        for (const p of proxied) {
            const index = p.findIndex((item) => item.id === item.replacesId);
            if (index >= 0) {
                p[index] = item;
            } else {
                p.push(item);
            }
        }
    }
};
const onRemoved = async (id: number) => {
    for (const p of proxied) {
        const index = p.findIndex((item) => item.id === id);
        if (index >= 0) {
            p.splice(index, 1);
        }
    }
};
export function proxy(data: Notification[]) {
    proxied.push(data);
    if (proxied.length > 0) {
        on("added", onAdded);
        on("removed", onRemoved);
    }
}
export function unproxy(data: Notification[]) {
    const index = proxied.indexOf(data);
    if (index >= 0) {
        proxied.splice(index, 1);
    }
    if (proxied.length === 0) {
        off("added", onAdded);
        off("removed", onRemoved);
    }
}
