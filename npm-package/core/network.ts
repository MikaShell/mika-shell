import call from "./call";
type DeviceType = "ethernet" | "wifi";
export type NM80211ApSecurityFlags =
    | "Pair_WEP40"
    | "Pair_WEP104"
    | "Pair_TKIP"
    | "Pair_CCMP"
    | "Group_WEP40"
    | "Group_WEP104"
    | "Group_TKIP"
    | "Group_CCMP"
    | "Key_Mgmt_PSK"
    | "Key_Mgmt_8021X"
    | "Key_Mgmt_SAE"
    | "Key_Mgmt_OWE"
    | "Key_Mgmt_OWE_Transition"
    | "Key_Mgmt_EAP_Suite_B_192";
export interface AccessPoint {
    bandwidth: number;
    frequency: number;
    hw_address: string;
    max_bitrate: number;
    last_seen: number;
    mode: string;
    rsn: NM80211ApSecurityFlags[];
    wpa: NM80211ApSecurityFlags[];
    ssid: string;
    strength: number;
}
import * as os from "./os";
export class Device {
    dbus_path: string;
    interface: string;
    driver: string;
    driver_version: string;
    hw_address: string;
    path: string;
    type: DeviceType;
    public active(connection: Connection) {
        return activateConnection(connection.dbus_path, this.dbus_path);
    }
    public getAccessPoints(): Promise<AccessPoint[]> {
        return call("network.getWirelessAccessPoints", this.dbus_path);
    }
    public getActiveAccessPoint(): Promise<AccessPoint | null> {
        return call("network.getWirelessActiveAccessPoint", this.dbus_path);
    }
    public rescan() {
        return call("network.wirelessRequestScan", this.dbus_path);
    }
    public async getConnection() {
        return (await getConnections()).find((c) => c.type === "802-11-wireless");
    }
}
export class ConnectionWireless {
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
}
export class Connection {
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
    wireless: ConnectionWireless | null;
    public getWirelessPsk() {
        return getWirelessPsk(this.dbus_path);
    }
}
export interface IPConfig {
    address: { address: string; prefix: number }[];
    gateway: string;
}
export class ActiveConnection {
    dbus_path: string;
    connection: Connection;
    default4: boolean;
    default6: boolean;
    device: Device;
    // 只支持无线和有线, 所以每个连接只有一个设备, 故弃用 devices 属性
    // 使用 device 属性代替
    // devices: Device[];
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
    specific_object: string;
    ip4_config: IPConfig | null;
    ip6_config: IPConfig | null;
    type: "802-11-wireless" | "802-3-ethernet";
    public diactivate() {
        return deactivateConnection(this.dbus_path);
    }
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

async function getDevices(): Promise<Device[]> {
    const ds: Device[] = [];
    const devices = await call("network.getDevices");
    for (const device of devices) {
        ds.push(Object.assign(new Device(), device));
    }
    return ds;
}
async function getConnections(): Promise<Connection[]> {
    const cs: Connection[] = [];
    const connections = await call("network.getConnections");
    for (const connection of connections) {
        if (connection.type === "802-11-wireless") {
            connection.wireless = Object.assign(new ConnectionWireless(), connection.wireless);
        }
        cs.push(Object.assign(new Connection(), connection));
    }
    return cs;
}
function getWirelessPsk(dbus_path: string): Promise<string | null> {
    return call("network.getWirelessPsk", dbus_path);
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
export async function getPrimaryConnection(): Promise<Connection | null> {
    const conn = await call("network.getPrimaryConnection");
    if (conn === null) return null;
    conn.device = conn.devices.map((d: any) => Object.assign(new Device(), d)).shift();
    return Object.assign(new Connection(), conn);
}
export async function getActiveConnections(): Promise<ActiveConnection[]> {
    const acs: ActiveConnection[] = [];
    const active_connections = await call("network.getActiveConnections");
    for (const ac of active_connections) {
        ac.connection = Object.assign(new Connection(), ac.connection);
        ac.device = ac.devices.map((d: any) => Object.assign(new Device(), d)).shift();
        acs.push(Object.assign(new ActiveConnection(), ac));
    }
    return acs;
}

function activateConnection(
    connection: string,
    device: string,
    specific_path: string = "/"
): Promise<void> {
    return call("network.activateConnection", connection, device, specific_path);
}
function deactivateConnection(active_connection: string): Promise<void> {
    return call("network.deactivateConnection", active_connection);
}
export type ConnectivityState = "unknown" | "none" | "portal" | "limqited" | "full";
export function checkConnectivity(): Promise<ConnectivityState> {
    return call("network.checkConnectivity");
}

export namespace wifi {
    export async function devices() {
        return (await getDevices()).filter((d) => d.type === "wifi");
    }
    // TODO: 使用更好的方法获取 Wifi 状态
    export async function isEnabled() {
        const result = (await os.exec(["rfkill", "list", "wifi"], { needOutput: true })) as string;
        return !result.includes(": yes");
    }
    export function enable() {
        return os.exec(["rfkill", "unblock", "wifi"]);
    }
    export function disable() {
        return os.exec(["rfkill", "block", "wifi"]);
    }
}
export namespace ethernet {}
