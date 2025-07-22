import call from "./call";
export function lookup(name: string, size: number, scale: number = 1): Promise<string> {
    return call("icon.lookup", name, size, scale);
}
