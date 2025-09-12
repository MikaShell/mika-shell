import call from "./call";
export type Edge = "left" | "right" | "top" | "bottom";
export type Layers = "background" | "bottom" | "top" | "overlay";
export type KeyboardMode = "none" | "exclusive" | "ondemand";
const EdgeToNumber: Record<Edge, number> = {
    left: 0,
    right: 1,
    top: 2,
    bottom: 3,
};
const LayersToNumber = {
    background: 0,
    bottom: 1,
    top: 2,
    overlay: 3,
};
const KeyboardModeToNumber = {
    none: 0,
    exclusive: 1,
    ondemand: 2,
};
export type Options = {
    anchor: Array<Edge>;
    layer: Layers;
    monitor: number;
    keyboardMode: KeyboardMode;
    namespace: string;
    margin: [number, number, number, number];
    exclusiveZone: number;
    autoExclusiveZone: boolean;
    backgroundTransparent: boolean;
    hidden: boolean;
    height: number;
    width: number;
};

export function init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        anchor: options.anchor?.map((e) => EdgeToNumber[e]) ?? [],
        layer: options.layer !== undefined ? LayersToNumber[options.layer] : 0,
        monitor: options.monitor ?? 0,
        keyboardMode:
            options.keyboardMode !== undefined ? KeyboardModeToNumber[options.keyboardMode] : 0,
        namespace: options.namespace ?? "mika-shell",
        margin: options.margin ?? [0, 0, 0, 0],
        exclusiveZone: options.exclusiveZone ?? 0,
        autoExclusiveZone: options.autoExclusiveZone ?? false,
        backgroundTransparent: options.backgroundTransparent ?? false,
        hidden: options.hidden ?? false,
        height: options.height ?? 0,
        width: options.width ?? 0,
    };

    return call("layer.init", opt);
}
export function show(): Promise<void> {
    return call("mika.show", 0);
}
export function hide(): Promise<void> {
    return call("mika.hide", 0);
}
export function close(): Promise<void> {
    return call("mika.close", 0);
}
export function openDevTools(): Promise<void> {
    return call("mika.openDevTools", 0);
}
export function resetAnchor(): Promise<void> {
    return call("layer.resetAnchor");
}
export function setAnchor(edge: Edge, anchor: boolean): Promise<void> {
    return call("layer.setAnchor", EdgeToNumber[edge], anchor);
}
export function setLayer(layer: Layers): Promise<void> {
    return call("layer.setLayer", LayersToNumber[layer]);
}
export function setKeyboardMode(mode: KeyboardMode): Promise<void> {
    return call("layer.setKeyboardMode", KeyboardModeToNumber[mode]);
}
export function setNamespace(namespace: string): Promise<void> {
    return call("layer.setNamespace", namespace);
}
export function setMargin(edge: Edge, margin: number): Promise<void> {
    return call("layer.setMargin", EdgeToNumber[edge], margin);
}
export function setExclusiveZone(zone: number): Promise<void> {
    return call("layer.setExclusiveZone", zone);
}
export function autoExclusiveZoneEnable(): Promise<void> {
    return call("layer.autoExclusiveZoneEnable");
}
export function setSize(width: number, height: number): Promise<void> {
    return call("layer.setSize", width, height);
}
export function getSize(): Promise<{ width: number; height: number }> {
    return call("layer.getSize");
}
export function setInputRegion(): Promise<void> {
    return call("layer.setInputRegion");
}
export function getScale(): Promise<number> {
    return call("layer.getScale");
}
import { Mika } from "./events-define";
import * as mika from "./mika";
type Events = "show" | "hide" | "show-request" | "hide-request" | "close-request";
type EventMap = {
    [K in Events]: K extends "hide" | "show"
        ? () => void
        : K extends "show-request" | "hide-request" | "close-request"
        ? (prev: boolean) => boolean | Promise<boolean>
        : never;
};
const listeners: Map<number, Array<() => void>> = new Map(); // only handle xxx-request event
const onceListeners: Map<number, Array<() => void>> = new Map(); // only handle xxx-request event

mika.on("show", (id: number) => {
    if (id !== globalThis.mikaShell.id) return;
    listeners.get(Mika["show"])?.forEach((cb) => cb());
    onceListeners.get(Mika["show"])?.forEach((cb) => cb());
    onceListeners.delete(Mika["show"]);
});
mika.on("hide", (id: number) => {
    if (id !== globalThis.mikaShell.id) return;
    listeners.get(Mika["hide"])?.forEach((cb) => cb());
    onceListeners.get(Mika["hide"])?.forEach((cb) => cb());
    onceListeners.delete(Mika["hide"]);
});
export function on<K extends Events>(event: K, callback: EventMap[K]) {
    if (event === "show-request" || event === "hide-request" || event === "close-request") {
        mika.on(event as any, callback);
        return;
    }
    if (!listeners.has(Mika[event])) {
        listeners.set(Mika[event], []);
    }
    listeners.get(Mika[event])!.push(callback as () => void);
}
export function off<K extends Events>(event: K, callback: EventMap[K]) {
    if (event === "show-request" || event === "hide-request" || event === "close-request") {
        mika.off(event as any, callback);
        return;
    }
    if (!listeners.has(Mika[event])) {
        return;
    }
    const index = listeners.get(Mika[event])!.indexOf(callback as () => void);
    if (index !== -1) {
        listeners.get(Mika[event])!.splice(index, 1);
    }
}
export function once<K extends Events>(event: K, callback: EventMap[K]) {
    if (event === "show-request" || event === "hide-request" || event === "close-request") {
        mika.once(event as any, callback);
        return;
    }
    if (!onceListeners.has(Mika[event])) {
        onceListeners.set(Mika[event], []);
    }
    onceListeners.get(Mika[event])!.push(callback as () => void);
}
