export * as call from "./call";

// Connect to unix socket
// The websocket returns Blob type, when Blob.size == 0, it means the sending is completed, and the connection needs to be actively disconnected, otherwise the connection will keep staying.
export function socket(
    path: string,
    type: "string" | "binary" = "string",
    binaryType: BinaryType = "blob"
) {
    if (!path.startsWith("/")) throw new Error("Path must start with `/`: " + path);
    const ws = new WebSocket(
        `ws://localhost:${globalThis.mikaShell.backendPort}${path}?type=${type}`
    );
    ws.binaryType = binaryType;
    return ws;
}
