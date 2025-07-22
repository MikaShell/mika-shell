import call from "./call";
export interface Entry {
    id: string;
    dbusName: string | null;
    type: "none" | "application" | "link" | "directory";
    version: string | null;
    name: string;
    genericName: string | null;
    noDisplay: boolean;
    comment: string | null;
    icon: string | null;
    hidden: boolean;
    onlyShowIn: string[];
    notShowIn: string[];
    dbusActivatable: boolean;
    tryExec: string | null;
    exec: string | null;
    path: string | null;
    terminal: boolean;
    actions: {
        id: string;
        name: string;
        icon: string | null;
        exec: string | null;
    }[];
    mimeType: string[];
    categories: string[];
    implements: string[];
    keywords: string[];
    startupNotify: boolean;
    startupWMClass: string | null;
    url: string | null;
    prefersNonDefaultGPU: boolean;
    singleMainWindow: boolean;
}
export function list(): Promise<Entry[]> {
    return call("apps.list");
}
export function activate(entryID: string, action: string | null = null, ...urls: string[]) {
    return call("apps.activate", entryID, action ?? "", urls);
}
