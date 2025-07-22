export type Window = {
    address: string;
    mapped: boolean;
    hidden: boolean;
    at: [number, number];
    size: [number, number];
    workspace: {
        id: number;
        name: string;
    };
    floating: boolean;
    pseudo: boolean;
    monitor: number;
    class: string;
    title: string;
    initialClass: string;
    initialTitle: string;
    pid: number;
    xwayland: boolean;
    pinned: boolean;
    fullscreen: number;
    fullscreenClient: number;
    grouped: string[];
    tags: string[];
    swallowing: string;
    focusHistoryID: number;
    inhibitingIdle: boolean;
    xdgTag: string;
    xdgDescription: string;
};
export type Workspace = {
    id: number;
    name: string;
    monitor: string;
    monitorID: number;
    windows: number;
    hasfullscreen: boolean;
    lastwindow: string;
    lastwindowtitle: string;
    ispersistent: boolean;
};

export type Animation = {
    name: string;
    overridden: boolean;
    bezier: string;
    enabled: boolean;
    speed: number;
    style: string;
};
export type Bezier = {
    name: string;
};
export type Bind = {
    locked: boolean;
    mouse: boolean;
    release: boolean;
    repeat: boolean;
    longPress: boolean;
    non_consuming: boolean;
    has_description: boolean;
    modmask: number;
    submap: string;
    key: string;
    keycode: number;
    catch_all: boolean;
    description: string;
    dispatcher: string;
    arg: string;
};

export type Client = {
    address: string;
    mapped: boolean;
    hidden: boolean;
    at: [number, number];
    size: [number, number];
    workspace: {
        id: number;
        name: string;
    };
    floating: boolean;
    pseudo: boolean;
    monitor: number;
    class: string;
    title: string;
    initialClass: string;
    initialTitle: string;
    pid: number;
    xwayland: boolean;
    pinned: boolean;
    fullscreen: number;
    fullscreenClient: number;
    grouped: string[];
    tags: string[];
    swallowing: string;
    focusHistoryID: number;
    inhibitingIdle: boolean;
    xdgTag: string;
    xdgDescription: string;
};
export type Decoration = {
    decorationName: string;
    priority: number;
};
export type DeviceInfo = {
    address: string;
    name: string;
};

export type Mouse = DeviceInfo & {
    defaultSpeed: number;
};

export type Keyboard = DeviceInfo & {
    rules: string;
    model: string;
    layout: string;
    variant: string;
    options: string;
    active_keymap: string;
    capsLock: boolean;
    numLock: boolean;
    main: boolean;
};

export type Tablet = DeviceInfo;

export type Devices = {
    mice: Mouse[];
    keyboards: Keyboard[];
    tablets: Tablet[];
    touch: unknown[];
    switches: unknown[];
};

export type Layers = {
    [outputName: string]: {
        levels: {
            [level: string]: {
                address: string;
                x: number;
                y: number;
                w: number;
                h: number;
                namespace: string;
                pid: number;
            }[];
        };
    };
};
export type Monitor = {
    id: number;
    name: string;
    description: string;
    make: string;
    model: string;
    serial: string;
    width: number;
    height: number;
    refreshRate: number;
    x: number;
    y: number;
    activeWorkspace: {
        id: number;
        name: string;
    };
    specialWorkspace: {
        id: number;
        name: string;
    };
    reserved: [number, number, number, number];
    scale: number;
    transform: number;
    focused: boolean;
    dpmsStatus: boolean;
    vrr: boolean;
    solitary: string;
    activelyTearing: boolean;
    directScanoutTo: string;
    disabled: boolean;
    currentFormat: string;
    mirrorOf: string;
    availableModes: string[];
};
export type Version = {
    branch: string;
    commit: string;
    version: string;
    dirty: boolean;
    commit_message: string;
    commit_date: string;
    tag: string;
    commits: string;
    buildAquamarine: string;
    buildHyprlang: string;
    buildHyprutils: string;
    buildHyprcursor: string;
    buildHyprgraphics: string;
    flags: string[];
};
