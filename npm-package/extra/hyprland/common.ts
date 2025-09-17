const os = globalThis.mikaShell.os;
let xdgRuntimeDir: string | undefined;
let his: string | undefined;
export async function getSocket(type: "event" | "command"): Promise<WebSocket> {
    if (!xdgRuntimeDir || !his) {
        xdgRuntimeDir = await os.getEnv("XDG_RUNTIME_DIR");
        his = await os.getEnv("HYPRLAND_INSTANCE_SIGNATURE");
    }
    return globalThis.mikaShell.utils.socket(
        `${xdgRuntimeDir}/hypr/${his}/.socket${type === "event" ? "2" : ""}.sock`
    );
}
