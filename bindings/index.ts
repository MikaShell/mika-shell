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
function socket(path: string) {
    return new WebSocket(["ws://localhost:6797", path].join("/"));
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
};
// @ts-ignore
window.mikaShell = mikaShell;
export default mikaShell;
