import * as _mika from "./mika";
import * as _tray from "./tray";
import * as _icon from "./icon";
import * as _os from "./os";
import * as _window from "./window";
import * as _layer from "./layer";
import * as _popover from "./popover";
import * as _apps from "./apps";
import * as _monitor from "./monitor";
import * as _notifd from "./notifd";
import * as _network from "./network";
import * as _foreignToplevel from "./foreign-toplevel";
import * as _libinput from "./libinput";
import * as _utils from "./utils";
import * as _workspace from "./workspace";
import * as _polkitAgent from "./polkit-agent";

const core = {
    mika: _mika,
    tray: _tray,
    icon: _icon,
    os: _os,
    window: _window,
    layer: _layer,
    popover: _popover,
    apps: _apps,
    monitor: _monitor,
    notifd: _notifd,
    network: _network,
    foreignToplevel: _foreignToplevel,
    libinput: _libinput,
    workspace: _workspace,
    utils: _utils,
    polkitAgent: _polkitAgent,
};

declare global {
    var mikaShell: typeof core & {
        backendPort: number;
        id: number;
    };
}

export default core;
export * as mika from "./mika";
export * as tray from "./tray";
export * as icon from "./icon";
export * as os from "./os";
export * as window from "./window";
export * as layer from "./layer";
export * as popover from "./popover";
export * as apps from "./apps";
export * as monitor from "./monitor";
export * as notifd from "./notifd";
export * as network from "./network";
export * as foreignToplevel from "./foreign-toplevel";
export * as libinput from "./libinput";
export * as workspace from "./workspace";
export * as utils from "./utils";
export * as polkitAgent from "./polkit-agent";
