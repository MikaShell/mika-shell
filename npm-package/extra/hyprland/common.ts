const os = globalThis.mikaShell.os;
let xdgRuntimeDir: string | null = null;
let his: string | null = null;

export async function getSocket(type: "event" | "command"): Promise<WebSocket> {
    if (xdgRuntimeDir === null || his === null) {
        xdgRuntimeDir = await os.getEnv("XDG_RUNTIME_DIR");
        his = await os.getEnv("HYPRLAND_INSTANCE_SIGNATURE");
        if (xdgRuntimeDir === null || his === null) {
            throw new Error(
                "Failed to get XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE, is Hyprland running?"
            );
        }
    }
    return globalThis.mikaShell.utils.socket(
        `${xdgRuntimeDir}/hypr/${his}/.socket${type === "event" ? "2" : ""}.sock`
    );
}
