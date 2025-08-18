import call from "./call";
import * as events from "./events";

export type Options = {
    title: string;
    class: string;
    resizable: boolean;
    backgroundTransparent: boolean;
    hidden: boolean;
    width: number;
    height: number;
};
var isLoaded = false;
window.addEventListener("load", () => (isLoaded = true));
function _init(options: Partial<Options>): Promise<void> {
    return call("window.init", options);
}
export function init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        title: options.title ?? "MikaShell Window",
        class: options.class ?? "mika-shell",
        resizable: options.resizable ?? true,
        backgroundTransparent: options.backgroundTransparent ?? false,
        hidden: options.hidden ?? false,
        width: options.width ?? 800,
        height: options.height ?? 600,
    };
    if (opt.resizable !== true && !isLoaded) {
        // 确保网页渲染完成后再显示, 防止窗口大小不正确
        return new Promise((resolve, reject) => {
            window.addEventListener("load", () => {
                _init(opt).then(resolve).catch(reject);
            });
        });
    } else {
        return _init(opt);
    }
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
    return call("window.openDevTools");
}
export function getSize(): Promise<{ width: number; height: number }> {
    return call("window.getSize");
}
export function setSize(width: number, height: number): Promise<void> {
    return call("window.setSize", width, height);
}
export function setInputRegion(): Promise<void> {
    return call("layer.setInputRegion");
}
export function getScale(): Promise<number> {
    return call("layer.getScale");
}
import * as layer from "./layer";
export const on = layer.on;
export const off = layer.off;
export const once = layer.once;
