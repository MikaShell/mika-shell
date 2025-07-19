import call from "./call";
export * from "./layer-and-window";
export type Options = {
    title: string;
    class: string;
    resizable: boolean;
    backgroundTransparent: boolean;
    hidden: boolean;
};

export function init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        title: options.title ?? "MikaShell Window",
        class: options.class ?? "mika-shell",
        resizable: options.resizable ?? true,
        backgroundTransparent: options.backgroundTransparent ?? false,
        hidden: options.hidden ?? false,
    };
    return call("window.init", opt);
}
export function show(): Promise<void> {
    return call("window.show");
}
export function hide(): Promise<void> {
    return call("window.hide");
}
export function close(): Promise<void> {
    return call("window.close");
}
export function openDevTools(): Promise<void> {
    return call("window.openDevTools");
}
