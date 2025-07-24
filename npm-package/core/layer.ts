import call from "./call";
import * as events from "./events";

type TryableEvents = "try-close" | "try-hide" | "try-show";
type Events = TryableEvents | "show" | "hide";
type Callback<T extends Events> = T extends TryableEvents
    ? () => boolean | Promise<boolean>
    : () => void;
const emitter = new events.Emitter("layer");
async function addListener<K extends Events>(
    event: K,
    callback: Callback<K>,
    once: boolean = false
) {
    if (event === "try-close" || event === "try-hide" || event === "try-show") {
        events.addTryableListener(
            await call("layer.getId"),
            event,
            callback as Callback<TryableEvents>,
            once
        );
    } else {
        if (once) emitter.once(event, callback);
        else emitter.on(event, callback);
    }
}

async function removeListener<K extends Events>(event: K, callback: Callback<K>) {
    if (event === "try-close" || event === "try-hide" || event === "try-show") {
        events.removeTryableListener(
            await call("layer.getId"),
            event,
            callback as Callback<TryableEvents>
        );
    } else {
        emitter.off(event, callback);
    }
}

export function on<K extends Events>(event: K, callback: Callback<K>) {
    return addListener(event, callback);
}
export function off<K extends Events>(event: K, callback: Callback<K>) {
    return removeListener(event, callback);
}

export function once<K extends Events>(event: K, callback: Callback<K>) {
    return addListener(event, callback, true);
}

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
    monitor: number;
    keyboardMode: number;
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
        monitor: options.monitor !== undefined ? options.monitor : 0,
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
    return call("layer.show");
}
export function hide(): Promise<void> {
    return call("layer.hide");
}
export function close(): Promise<void> {
    return call("layer.close");
}
export function openDevTools(): Promise<void> {
    return call("layer.openDevTools");
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
