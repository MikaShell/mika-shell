export * as call from "./call";
export function socket(path: string) {
    return new WebSocket(`ws://localhost:6797/${path}`);
}
