import call from "./call";
export interface Monitor {
    scale: number;
    width: number;
    height: number;
    widthMm: number;
    heightMm: number;
    connector: string;
    description: string;
    model: string;
    refreshRate: number;
}
export function list(): Promise<Monitor[]> {
    return call("monitor.list");
}
export function get(): Promise<Monitor> {
    return call("monitor.get");
}
