import * as command from "./command";
import * as event from "./event";

export type Workspaces = Array<boolean | null>;
const proxiers: Workspaces[] = [];
export function proxy(workspaces: Workspaces) {
    if (proxiers.indexOf(workspaces) !== -1) return;
    if (proxiers.length === 0) init();
    proxiers.push(workspaces);
    command.workspaces().then(async (ws) => {
        ws.forEach((w) => add(workspaces, w.id));
        const active = await command.activeworkspace();
        focus(workspaces, active.id);
    });
}
export function unproxy(workspaces: Workspaces) {
    const index = proxiers.indexOf(workspaces);
    if (index !== -1) {
        proxiers.splice(index, 1);
    }
    if (proxiers.length === 0) deinit();
}
function add(ws: Workspaces, id: number) {
    if (ws.length === id || ws[id - 1] === null) {
        // FIXME: 由于 WebSocket 后端的 bug, 可能会有重复, 所以这里需要判断一下
        return;
    }
    if (ws.length > id - 1) {
        ws[id - 1] = false;
    } else {
        if (ws.length < id - 1) {
            for (let i = ws.length; i < id - 1; i++) {
                ws.push(null);
            }
        }
        for (let i = 0; i < ws.length; i++) {
            if (ws[i] === true && i !== id - 1) {
                ws[i]! = false;
            }
        }
        ws.push(true);
    }
}
function remove(ws: Workspaces, id: number) {
    if (ws.length < id) {
        // FIXME: 由于 WebSocket 后端的 bug, 可能会有重复, 所以这里需要判断一下
        return;
    }
    ws[id - 1] = null;
    while (ws.length > 0 && ws[ws.length - 1] === null) {
        ws.pop();
    }
}
function focus(ws: Workspaces, id: number) {
    if (ws[id - 1]) return; // FIXME: 由于 WebSocket 后端的 bug, 可能会有重复, 所以这里需要判断一下
    for (let i = 0; i < ws.length; i++) {
        if (i === id - 1) ws[i] = true;
        else if (ws[i] === true) ws[i] = false;
    }
}
type WorkspaceEvent = {
    workspaceId: number;
    workspaceName: string;
};
function onWorkspace(data: WorkspaceEvent) {
    const { workspaceId } = data;
    for (const ws of proxiers) {
        focus(ws, workspaceId);
    }
}
async function onCreateWorkspace(e: WorkspaceEvent) {
    proxiers.forEach(async (ws) => {
        add(ws, e.workspaceId);
    });
}
function onDestroyWorkspace(data: WorkspaceEvent) {
    const { workspaceId } = data;
    proxiers.forEach((ws) => {
        remove(ws, workspaceId);
    });
}
function init() {
    event.on("workspacev2", onWorkspace);
    event.on("createworkspacev2", onCreateWorkspace);
    event.on("destroyworkspacev2", onDestroyWorkspace);
}
function deinit() {
    event.off("workspacev2", onWorkspace);
    event.off("createworkspacev2", onCreateWorkspace);
    event.off("destroyworkspacev2", onDestroyWorkspace);
}
