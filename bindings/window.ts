import call from "./call";
export type Options = {
    title: string;
    resizable: boolean;
    backgroundTransparent: boolean;
    hidden: boolean;
};

export function init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        title: options.title ?? "AikaShell Window",
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
