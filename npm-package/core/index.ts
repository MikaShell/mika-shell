import * as _mika from "./mika";
import * as _tray from "./tray";
import * as _icon from "./icon";
import * as _os from "./os";
import * as _window from "./window";
import * as _layer from "./layer";
import * as _apps from "./apps";
import * as _monitor from "./monitor";
import * as _notifd from "./notifd";
import * as _network from "./network";
import * as _dock from "./dock";
import * as _libinput from "./libinput";
import * as _utils from "./utils";
const core = {
    mika: _mika,
    tray: _tray,
    icon: _icon,
    os: _os,
    window: _window,
    layer: _layer,
    apps: _apps,
    monitor: _monitor,
    notifd: _notifd,
    network: _network,
    dock: _dock,
    libinput: _libinput,
    utils: _utils,
};
declare global {
    var mikaShell: typeof core;
}
export default core;
export * as tray from "./tray";
export const mika = core.mika;
export const icon = core.icon;
export const os = core.os;
export const window = core.window;
export const layer = core.layer;
export const apps = core.apps;
export const monitor = core.monitor;
export const notifd = core.notifd;
export const network = core.network;
export const dock = core.dock;
export const libinput = core.libinput;
export const utils = core.utils;
