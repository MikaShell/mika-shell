export * as call from "./call";
export function socket(path: string) {
    // @ts-ignore
    return new WebSocket(`ws://localhost:${window.mikaShell.backPort}/${path}`);
}
