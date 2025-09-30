import call from "./call";
import { Workspace as WorkspaceEvents } from "./events-define";

export type Workspace = {
    id: number;
    workspaceId: string | null;
    name: string;
    state: {
        active: boolean;
        urgent: boolean;
        hidden: boolean;
    };
    coordinates: number[];
    capabilities: {
        activate: boolean;
        deactivate: boolean;
        remove: boolean;
        assign: boolean;
    };
};
export type Group = {
    id: number;
    capabilities: {
        create_workspace: boolean;
    };
    // `workspaces` is array of `Workspace.id`
    workspaces: number[];
};

export function groups(): Promise<Group[]> {
    return call("workspace.groups");
}

// `group` is `Group.id`
export function getGroup(group: number): Promise<Group> {
    return call("workspace.getGroup", group);
}

// `group` is `Group.id`
export function createWorkspace(group: number, name: string): Promise<Workspace> {
    return call("workspace.createWorkspace", group, name);
}

// `workspace` is `Workspace.id`, not `Workspace.workspaceId`
export function getWorkspace(workspace: number): Promise<Workspace> {
    return call("workspace.getWorkspace", workspace);
}

// `workspace` is `Workspace.id`, not `Workspace.workspaceId`
export function activate(workspace: number): Promise<void> {
    return call("workspace.activate", workspace);
}

// `workspace` is `Workspace.id`, not `Workspace.workspaceId`
export function deactivate(workspace: number): Promise<void> {
    return call("workspace.deactivate", workspace);
}

// `workspace` is `Workspace.id`, not `Workspace.workspaceId`
// `group` is `Group.id`
export function assign(workspace: number, group: number): Promise<void> {
    return call("workspace.assign", workspace, group);
}

// `workspace` is `Workspace.id`, not `Workspace.workspaceId`
export function remove(workspace: number): Promise<void> {
    return call("workspace.remove", workspace);
}

export function list(): Promise<Workspace[]> {
    return call("workspace.list");
}

type Events = keyof typeof WorkspaceEvents;
type EventMap = {
    [K in Events]: K extends "workspace-changed"
        ? (workspace: Workspace) => void
        : K extends "workspace-added"
        ? (workspace: Workspace) => void
        : K extends "workspace-removed"
        ? (workspace: Workspace) => void
        : K extends "group-added"
        ? (group: Group) => void
        : K extends "group-removed"
        ? (group: Group) => void
        : K extends "group-enter"
        ? (group: Group) => void
        : K extends "group-leave"
        ? (group: Group) => void
        : K extends "group-workspace-enter"
        ? (group: Group, workspace: Workspace) => void
        : K extends "group-workspace-leave"
        ? (group: Group, workspace: Workspace) => void
        : never;
};
import * as events from "./events";
export function on<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.on(WorkspaceEvents[event], callback);
}
export function off<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.off(WorkspaceEvents[event], callback);
}
export function once<K extends Events>(event: K, callback: (e: EventMap[K]) => void) {
    events.once(WorkspaceEvents[event], callback);
}
