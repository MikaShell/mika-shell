export interface Pixmap {
    width: number;
    height: number;
    webp: number[];
}
export interface Attention {
    iconName: string;
    iconPixmap: Pixmap;
    movieName: string;
}
export interface Icon {
    name: string;
    themePath: string;
    pixmap: Pixmap;
}
export interface Overlay {
    iconName: string;
    iconPixmap: Pixmap;
}
export interface Tooltip {
    iconName: string;
    iconPixmap: Pixmap;
    title: string;
    text: string;
}
export interface Item {
    service: string;
    attention: Attention;
    category: string;
    icon: Icon;
    id: string;
    ItemIsMenu: boolean;
    menu: string;
    overlay: Overlay;
    status: string;
    title: string;
    tooltip: Tooltip;
}
export interface MenuProperties {
    label: string | null;
    visible: boolean;
    enabled: boolean;
    iconName: string | null;
    iconData: string | null;
    iconSize: number | null;
    childrenDisplay: string | null;
    toggleType: "checkmark" | "radio" | null;
    toggleState: "unchecked" | "checked" | "indeterminate" | null;
    group: string | null;
    shortcut: string[] | null;
    shortcutLabel: string | null;
    tooltip: string | null;
    type: string | null;
    childrenTypes: string[] | null;
    action: string | null;
}
export interface MenuNode {
    id: number;
    properties: Record<string, any>;
    children: MenuNode[];
}
export const ProxyData: Record<string, Item> = {};
import call from "./call";
export function getItem(service: string): Promise<Item> {
    return call("tray.getItem", service);
}
export function getItems(): Promise<Item[]> {
    return call("tray.getItems");
}
export function subscribe(): Promise<void> {
    return call("tray.subscribe");
}
export function unsubscribe(): Promise<void> {
    return call("tray.unsubscribe");
}
export function activate(service: string, x: number, y: number): Promise<void> {
    return call("tray.activate", service, x, y);
}
export function secondaryActivate(service: string, x: number, y: number): Promise<void> {
    return call("tray.secondaryActivate", service, x, y);
}
export function scroll(
    service: string,
    delta: number,
    orientation: "horizontal" | "vertical"
): Promise<void> {
    return call("tray.scroll", service, delta, orientation);
}
export function provideXdgActivationToken(service: string, token: string): Promise<void> {
    return call("tray.provideXdgActivationToken", service, token);
}
export function getMenu(service: string): Promise<MenuNode> {
    return call("tray.getMenu", service);
}
export function activateMenu(service: string, id: number): Promise<void> {
    return call("tray.activateMenu", service, id);
}
import { addEventListener, removeEventListener } from "./events";
var listenerCount = 0;
type Events = "added" | "changed" | "removed";

function addListener(name: Events, callback: (service: string) => void, once: boolean = false) {
    const eventName = `tray-${name}`;
    if (listenerCount === 0) subscribe();
    listenerCount++;
    addEventListener(eventName, callback, once);
}
function removeListener(name: Events, callback: (service: string) => void) {
    removeEventListener(`tray-${name}`, callback);
    if (listenerCount === 0) unsubscribe();
}
export function on<T extends Events>(event: T, callback: (service: string) => void) {
    addListener(event, callback, false);
}
export function off<T extends Events>(event: T, callback: (service: string) => void) {
    removeListener(event, callback);
}
export function once<T extends Events>(event: T, callback: (service: string) => void) {
    addListener(event, callback, true);
}
const proxied: Array<Record<string, Item>> = [];
const onAdded = async (service: string) => {
    const item = await getItem(service);
    for (const p of proxied) {
        p[service] = item;
    }
};
const onChanged = async (service: string) => {
    const item = await getItem(service);
    for (const p of proxied) {
        p[service] = item;
    }
};
const onRemoved = async (service: string) => {
    for (const p of proxied) {
        delete p[service];
    }
};
export function proxy(data: Record<string, Item>) {
    proxied.push(data);
    if (proxied.length > 0) {
        on("added", onAdded);
        on("changed", onChanged);
        on("removed", onRemoved);
    }
}
export function unproxy(data: Record<string, Item>) {
    const index = proxied.indexOf(data);
    if (index >= 0) {
        proxied.splice(index, 1);
    }
    if (proxied.length === 0) {
        off("added", onAdded);
        off("changed", onChanged);
        off("removed", onRemoved);
    }
}
