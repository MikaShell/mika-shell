import call from "./call";
import * as mika from "./mika";
import * as tray from "./tray";
import * as icon from "./icon";
import * as os from "./os";
import * as window_ from "./window";
import * as layer from "./layer";
import * as apps from "./apps";
import * as monitor from "./monitor";
import * as notifd from "./notifd";
import * as network from "./network";
import * as dock from "./dock";
import * as libinput from "./libinput";

function socket(path: string) {
    return new WebSocket(`ws://localhost:6797/${path}`);
}
const mikaShell = {
    tray,
    icon,
    os,
    window: window_,
    layer,
    mika,
    call,
    socket,
    apps,
    monitor,
    notifd,
    network,
    dock,
    libinput,
};
declare global {
    interface Window {
        // @ts-ignore
        mikaShell: typeof mikaShell;
    }
}
// @ts-ignore
window.mikaShell = core;
export {
    tray,
    icon,
    os,
    window_ as window,
    layer,
    mika,
    call,
    socket,
    apps,
    monitor,
    notifd,
    network,
    dock,
    libinput,
};
