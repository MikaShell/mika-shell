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
