export interface Pixmap {
    width: number;
    height: number;
    base64: string;
}
export interface Attention {
    iconName: string;
    iconPixmap: Pixmap;
    movieName: string;
}
export interface Icon {
    name: string;
    themePath: string;
    pixmap: Pixmap[];
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
import call from "./call";
import { lookup } from "./icon";
export async function pickIcon(item: Item, size: number): Promise<string> {
    const pixmap = item.icon.pixmap;
    if (!Array.isArray(pixmap) || pixmap.length === 0) {
        return await lookup(item.icon.name, size);
    }
    let closest = pixmap[0];
    let minDiff = Math.abs(closest.width - size);

    for (let i = 1; i < pixmap.length; i++) {
        const diff = Math.abs(pixmap[i].width - size);
        if (diff < minDiff) {
            closest = pixmap[i];
            minDiff = diff;
        }
    }

    return closest.base64;
}
export function getItem(service: string): Promise<Item> {
    return call("tray.getItem", service);
}
export function getItems(): Promise<Item[]> {
    return call("tray.getItems");
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
type Events = keyof typeof Tray;
import { Tray } from "./events-define";
import * as events from "./events";
export function on<K extends Events>(event: K, callback: (service: string) => void) {
    events.on(Tray[event], callback);
}
export function off<K extends Events>(event: K, callback: (service: string) => void) {
    events.off(Tray[event], callback);
}
export function once<K extends Events>(event: K, callback: (service: string) => void) {
    events.once(Tray[event], callback);
}
