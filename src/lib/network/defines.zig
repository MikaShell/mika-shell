// https://networkmanager.dev/docs/api/latest/nm-dbus-types.html?utm_source=chatgpt.com
pub const State = enum(u8) {
    unknown = 0,
    asleep = 10,
    disconnected = 20,
    disconnecting = 30,
    connecting = 40,
    connected_local = 50,
    connected_site = 60,
    connected_global = 70,
};
pub const DeviceType = enum(u8) {
    unknown = 0,
    ethernet = 1,
    wifi = 2,
    unused1 = 3,
    unused2 = 4,
    bt = 5,
    olpc_mesh = 6,
    wimax = 7,
    modem = 8,
    infiniband = 9,
    bond = 10,
    vlan = 11,
    adsl = 12,
    bridge = 13,
    generic = 14,
    team = 15,
    tun = 16,
    ip_tunnel = 17,
    macvlan = 18,
    vxlan = 19,
    veth = 20,
    macsec = 21,
    dummy = 22,
    ppp = 23,
    ovs_interface = 24,
    ovs_port = 25,
    ovs_bridge = 26,
    wpan = 27,
    sixlowpan = 28,
    wireguard = 29,
    wifi_p2p = 30,
    vrf = 31,
    loopback = 32,
    hsr = 33,
    ipvlan = 34,
    _,
};

const std = @import("std");
pub const ConnectionType = enum {
    @"6lowpan",
    @"802-11-olpc-mesh",
    @"802-11-wireless",
    @"802-3-ethernet",
    adsl,
    bluetooth,
    bond,
    bridge,
    cdma,
    dummy,
    generic,
    gsm,
    hsr,
    infiniband,
    @"ip-tunnel",
    ipvlan,
    loopback,
    macsec,
    macvlan,
    @"ovs-bridge",
    @"ovs-dpdk",
    @"ovs-interface",
    @"ovs-patch",
    @"ovs-port",
    pppoe,
    team,
    tun,
    veth,
    vlan,
    vpn,
    vrf,
    vxlan,
    @"wifi-p2p",
    wimax,
    wireguard,
    wpan,
    pub fn parse(s: []const u8) ConnectionType {
        const T = ConnectionType;
        const eql = std.mem.eql;
        if (eql(u8, s, @tagName(T.@"6lowpan"))) return .@"6lowpan";
        if (eql(u8, s, @tagName(T.@"802-11-olpc-mesh"))) return .@"802-11-olpc-mesh";
        if (eql(u8, s, @tagName(T.@"802-11-wireless"))) return .@"802-11-wireless";
        if (eql(u8, s, @tagName(T.@"802-3-ethernet"))) return .@"802-3-ethernet";
        if (eql(u8, s, @tagName(T.adsl))) return .adsl;
        if (eql(u8, s, @tagName(T.bluetooth))) return .bluetooth;
        if (eql(u8, s, @tagName(T.bond))) return .bond;
        if (eql(u8, s, @tagName(T.bridge))) return .bridge;
        if (eql(u8, s, @tagName(T.cdma))) return .cdma;
        if (eql(u8, s, @tagName(T.dummy))) return .dummy;
        if (eql(u8, s, @tagName(T.generic))) return .generic;
        if (eql(u8, s, @tagName(T.gsm))) return .gsm;
        if (eql(u8, s, @tagName(T.hsr))) return .hsr;
        if (eql(u8, s, @tagName(T.infiniband))) return .infiniband;
        if (eql(u8, s, @tagName(T.@"ip-tunnel"))) return .@"ip-tunnel";
        if (eql(u8, s, @tagName(T.ipvlan))) return .ipvlan;
        if (eql(u8, s, @tagName(T.loopback))) return .loopback;
        if (eql(u8, s, @tagName(T.macsec))) return .macsec;
        if (eql(u8, s, @tagName(T.macvlan))) return .macvlan;
        if (eql(u8, s, @tagName(T.@"ovs-bridge"))) return .@"ovs-bridge";
        if (eql(u8, s, @tagName(T.@"ovs-dpdk"))) return .@"ovs-dpdk";
        if (eql(u8, s, @tagName(T.@"ovs-interface"))) return .@"ovs-interface";
        if (eql(u8, s, @tagName(T.@"ovs-patch"))) return .@"ovs-patch";
        if (eql(u8, s, @tagName(T.@"ovs-port"))) return .@"ovs-port";
        if (eql(u8, s, @tagName(T.pppoe))) return .pppoe;
        if (eql(u8, s, @tagName(T.team))) return .team;
        if (eql(u8, s, @tagName(T.tun))) return .tun;
        if (eql(u8, s, @tagName(T.veth))) return .veth;
        if (eql(u8, s, @tagName(T.vlan))) return .vlan;
        if (eql(u8, s, @tagName(T.vrf))) return .vrf;
        if (eql(u8, s, @tagName(T.vxlan))) return .vxlan;
        if (eql(u8, s, @tagName(T.@"wifi-p2p"))) return .@"wifi-p2p";
        if (eql(u8, s, @tagName(T.wimax))) return .wimax;
        if (eql(u8, s, @tagName(T.wireguard))) return .wireguard;
        if (eql(u8, s, @tagName(T.wpan))) return .wpan;
        @panic("unsupported connection type");
    }
};
pub const ActiveConnectionState = enum(u8) {
    unknown = 0,
    activating = 1,
    activated = 2,
    deactivating = 3,
    deactivated = 4,
};
pub const ActiveConnectionStateFlags = packed struct {
    is_default: bool = false,
    is_default6: bool = false,
    is_activating: bool = false,
    is_master: bool = false,
    layer2_ready: bool = false,
    ip4_ready: bool = false,
    ip6_ready: bool = false,

    pub fn fromRaw(raw: u32) ActiveConnectionStateFlags {
        return .{
            .is_default = (raw & 0x1) != 0,
            .is_default6 = (raw & 0x2) != 0,
            .is_activating = (raw & 0x4) != 0,
            .is_master = (raw & 0x8) != 0,
            .layer2_ready = (raw & 0x10) != 0,
            .ip4_ready = (raw & 0x20) != 0,
            .ip6_ready = (raw & 0x40) != 0,
        };
    }
};
pub const ConnectivityState = enum(u8) {
    unknown = 0,
    none = 1,
    portal = 2,
    limited = 3,
    full = 4,
};
pub const @"80211Mode" = enum(u32) {
    unknown = 0,
    adhoc = 1,
    infra = 2,
    ap = 3,
    mesh = 4,
};
pub const @"80211ApSecurityFlags" = enum(u32) {
    None = 0x0000_0000, // No security
    Pair_WEP40 = 0x0000_0001, // 40/64-bit WEP (pairwise)
    Pair_WEP104 = 0x0000_0002, // 104/128-bit WEP (pairwise)
    Pair_TKIP = 0x0000_0004, // TKIP (pairwise)
    Pair_CCMP = 0x0000_0008, // AES/CCMP (pairwise)

    Group_WEP40 = 0x0000_0010, // 40/64-bit WEP (group)
    Group_WEP104 = 0x0000_0020, // 104/128-bit WEP (group)
    Group_TKIP = 0x0000_0040, // TKIP (group)
    Group_CCMP = 0x0000_0080, // AES/CCMP (group)

    Key_Mgmt_PSK = 0x0000_0100, // WPA/RSN with Pre-Shared Key
    Key_Mgmt_8021X = 0x0000_0200, // 802.1x EAP authentication
    Key_Mgmt_SAE = 0x0000_0400, // WPA3-SAE (personal)
    Key_Mgmt_OWE = 0x0000_0800, // WPA3-OWE (open)
    Key_Mgmt_OWE_Transition = 0x0000_1000, // WPA3-OWE transition mode
    Key_Mgmt_EAP_Suite_B_192 = 0x0000_2000, // WPA3 Enterprise Suite-B 192-bit

    _,
    const Self = @This();
    pub fn parse(allocator: std.mem.Allocator, flags: u32) ![]Self {
        var list = std.ArrayList(Self).init(allocator);

        if (flags == 0) {
            return list.toOwnedSlice();
        }

        if ((flags & @intFromEnum(Self.Pair_WEP40)) != 0) try list.append(.Pair_WEP40);
        if ((flags & @intFromEnum(Self.Pair_WEP104)) != 0) try list.append(.Pair_WEP104);
        if ((flags & @intFromEnum(Self.Pair_TKIP)) != 0) try list.append(.Pair_TKIP);
        if ((flags & @intFromEnum(Self.Pair_CCMP)) != 0) try list.append(.Pair_CCMP);

        if ((flags & @intFromEnum(Self.Group_WEP40)) != 0) try list.append(.Group_WEP40);
        if ((flags & @intFromEnum(Self.Group_WEP104)) != 0) try list.append(.Group_WEP104);
        if ((flags & @intFromEnum(Self.Group_TKIP)) != 0) try list.append(.Group_TKIP);
        if ((flags & @intFromEnum(Self.Group_CCMP)) != 0) try list.append(.Group_CCMP);

        if ((flags & @intFromEnum(Self.Key_Mgmt_PSK)) != 0) try list.append(.Key_Mgmt_PSK);
        if ((flags & @intFromEnum(Self.Key_Mgmt_8021X)) != 0) try list.append(.Key_Mgmt_8021X);
        if ((flags & @intFromEnum(Self.Key_Mgmt_SAE)) != 0) try list.append(.Key_Mgmt_SAE);
        if ((flags & @intFromEnum(Self.Key_Mgmt_OWE)) != 0) try list.append(.Key_Mgmt_OWE);
        if ((flags & @intFromEnum(Self.Key_Mgmt_OWE_Transition)) != 0) try list.append(.Key_Mgmt_OWE_Transition);
        if ((flags & @intFromEnum(Self.Key_Mgmt_EAP_Suite_B_192)) != 0) try list.append(.Key_Mgmt_EAP_Suite_B_192);

        return list.toOwnedSlice();
    }
};
