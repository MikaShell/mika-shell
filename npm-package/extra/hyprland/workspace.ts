import * as command from "./command";
import * as event from "./event";
export { Workspace } from "./types";
type Events = {
    create: event.EventMap["createworkspacev2"];
    destroy: event.EventMap["destroyworkspacev2"];
    active: event.EventMap["workspacev2"];
};
export function on<K extends keyof Events>(name: K, callback: (data: Events[K]) => void) {
    switch (name) {
        case "create":
            event.on("createworkspacev2", callback);
            break;
        case "destroy":
            event.on("destroyworkspacev2", callback);
            break;
        case "active":
            event.on("workspacev2", callback);
            break;
    }
}
export function once<K extends keyof Events>(name: K, callback: (data: Events[K]) => void) {
    switch (name) {
        case "create":
            event.once("createworkspacev2", callback);
            break;
        case "destroy":
            event.once("destroyworkspacev2", callback);
            break;
        case "active":
            event.once("workspacev2", callback);
            break;
    }
}
export function off<K extends keyof Events>(name: K, callback: (data: Events[K]) => void) {
    switch (name) {
        case "create":
            event.off("createworkspacev2", callback);
            break;
        case "destroy":
            event.off("destroyworkspacev2", callback);
            break;
        case "active":
            event.off("workspacev2", callback);
            break;
    }
}
export function active() {
    return command.activeworkspace();
}
export function list() {
    return command.workspaces();
}
export function activate(id: number | "next" | "prev") {
    let id_ = id.toString();
    switch (id) {
        case "next":
            id_ = "+1";
            break;
        case "prev":
            id_ = "-1";
            break;
    }
    return command.dispatch("workspace", id_);
}
