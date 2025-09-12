import call from "./call";
export interface Monitor {
    scale: number;
    width: number;
    height: number;
    widthMm: number;
    heightMm: number;
    connector: string | null;
    description: string | null;
    model: string | null;
    refreshRate: number;
}
export async function list(): Promise<Monitor[]> {
    return call("monitor.list");
}
export async function get(index: number): Promise<Monitor> {
    const monitors = await call("monitor.list");
    return monitors[index];
}
export async function getCurrent(): Promise<Monitor> {
    return call("monitor.getCurrent");
}
export type CaptureOption = {
    overlayCursor: boolean;
    encode: "webp" | "png";
    webpQuality: number;
    pngCompression: number;
};
export async function capture(
    output: number,
    region: null | { x: number; y: number; w: number; h: number } = null,
    option: Partial<CaptureOption> = {}
): Promise<string> {
    return call(
        "monitor.capture",
        output,
        region ? region.x : 0,
        region ? region.y : 0,
        region ? region.w : 0,
        region ? region.h : 0,
        option.overlayCursor || false,
        option.encode || "webp",
        option.webpQuality || 72,
        option.pngCompression || 0
    );
}
