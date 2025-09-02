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
export function list(): Promise<Monitor[]> {
    return call("monitor.list");
}
export function get(): Promise<Monitor> {
    return call("monitor.get");
}
export function capture(
    output: number,
    quality: number = 75,
    overlayCursor: boolean = false,
    region: null | { x: number; y: number; w: number; h: number } = null
): Promise<string> {
    return call(
        "monitor.capture",
        output,
        quality,
        overlayCursor,
        region ? region.x : 0,
        region ? region.y : 0,
        region ? region.w : 0,
        region ? region.h : 0
    );
}
