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
    layer: number;
    keyboardMode: number;
    namespace: string;
    margin: [number, number, number, number];
    exclusiveZone: number;
    autoExclusiveZone: boolean;
    backgroundTransparent: boolean;
    hidden: boolean;
};

export function init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        anchor: options.anchor?.map((e) => EdgeToNumber[e]) ?? [],
        layer: options.layer !== undefined ? LayersToNumber[options.layer] : 0,
        keyboardMode:
            options.keyboardMode !== undefined ? KeyboardModeToNumber[options.keyboardMode] : 0,
        namespace: options.namespace ?? "mika-shell",
        margin: options.margin ?? [0, 0, 0, 0],
        exclusiveZone: options.exclusiveZone ?? 0,
        autoExclusiveZone: options.autoExclusiveZone ?? false,
        backgroundTransparent: options.backgroundTransparent ?? false,
        hidden: options.hidden ?? false,
    };

    return call("layer.init", opt);
}
export function show(): Promise<void> {
    return call("layer.show");
}
export function hide(): Promise<void> {
    return call("layer.hide");
}
export function close(): Promise<void> {
    return call("layer.close");
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

import * as events from "./events";

type Events = {
    close: () => boolean | Promise<boolean>;
    hide: () => boolean | Promise<boolean>;
    show: () => boolean | Promise<boolean>;
};
async function addListener<K extends keyof Events>(
    event: K,
    callback: Events[K],
    once: boolean = false
) {
    if (event === "close" || event === "hide" || event === "show") {
        events.addTryableListener(await call("window.getId"), event, callback, once);
    } else {
        events.addEventListener(event, callback, once);
    }
}

async function removeListener<K extends keyof Events>(event: K, callback: Events[K]) {
    if (event === "close" || event === "hide" || event === "show") {
        events.removeTryableListener(await call("window.getId"), event, callback);
    } else {
        events.removeEventListener(event, callback);
    }
}

export function on<K extends keyof Events>(event: K, callback: Events[K]) {
    return addListener(event, callback);
}
export function off<K extends keyof Events>(event: K, callback: Events[K]) {
    return removeListener(event, callback);
}

export function once<K extends keyof Events>(event: K, callback: Events[K]) {
    return addListener(event, callback, true);
}
