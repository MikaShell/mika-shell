import call from "./call";
type DeviceType = "ethernet" | "wifi";
export interface Device {
    dbus_path: string;
    interface: string;
    driver: string;
    driver_version: string;
    hw_address: string;
    path: string;
    type: DeviceType;
}
export interface Connection {
    dbus_path: string;
    filename: string;
    id: string;
    type: "802-11-wireless" | "802-3-ethernet";
    zone: string | null;
    autoconnect: boolean;
    autoconnect_ports: "true" | "false" | "default";
    metered: "yes" | "no" | "default";
    autoconnect_priority: number;
    controller: string | null;
    wireless: {
        band: "5GHz" | "2.4GHz" | null;
        bssid: string | null;
        hidden: boolean;
        mode: "infrastructure" | "adhoc" | "ap" | "mesh";
        powersave: "default" | "ignore" | "disable" | "enable";
        ssid: string | null;
        security: {
            "key-mgmt":
                | "none"
                | "ieee8021x"
                | "wpa-psk"
                | "wpa-eap"
                | "wpa-eap-suite-b-192"
                | "sae"
                | "owe";
            psk: string | null;
        } | null;
    } | null;
}
export interface ActiveConnection {
    connection: Connection;
    default4: boolean;
    default6: boolean;
    devices: Device[];
    state: "unknown" | "activating" | "activated" | "deactivating" | "deactivated";
    state_flags: {
        is_default: boolean;
        is_default6: boolean;
        is_activating: boolean;
        is_master: boolean;
        layer2_ready: boolean;
        ip4_ready: boolean;
        ip6_ready: boolean;
    };
    type: "802-11-wireless" | "802-3-ethernet";
}
export type State =
    | "unknown"
    | "asleep"
    | "disconnected"
    | "disconnecting"
    | "connecting"
    | "connected_local"
    | "connected_site"
    | "connected_global";

export function getDevices(): Promise<Device[]> {
    return call("network.getDevices");
}
export function getState(): Promise<State> {
    return call("network.getState");
}
export function isEnabled(): Promise<boolean> {
    return call("network.isEnabled");
}
export function enable(): Promise<void> {
    return call("network.enable");
}
export function disable(): Promise<void> {
    return call("network.disable");
}
export function getConnections(): Promise<Connection[]> {
    return call("network.getConnections");
}
export function getPrimaryConnection(): Promise<Connection | null> {
    return call("network.getPrimaryConnection");
}
export function getActiveConnections(): Promise<ActiveConnection[]> {
    return call("network.getActiveConnections");
}
export function getWirelessPsk(dbus_path: string): Promise<string | null> {
    return call("network.getWirelessPsk", dbus_path);
}
