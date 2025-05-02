import { TrayItem } from "./bindings/github.com/HumXC/mikami/services/models";
import {
    Activate,
    ContextMenu,
    ProvideXdgActivationToken,
    Scroll,
    SecondaryActivate,
    Items as Items_,
} from "./bindings/github.com/HumXC/mikami/services/tray";
import { id, WailsEventOff, WailsEventOn, WaitReady } from "./common";
import * as tray from "./bindings/github.com/HumXC/mikami/services/tray";

export class Item extends TrayItem {
    // @ts-ignore
    Category: "ApplicationStatus" | "Communications" | "SystemServices" | "Hardware";
    // @ts-ignore
    Status: "Passive" | "Active" | "NeedsAttention";
    constructor(item: TrayItem) {
        super();
        this.Service = item.Service;
        this.Id = item.Id;
        this.Category = item.Category as any;
        this.IsMenu = item.IsMenu;
        this.Status = item.Status as any;
        this.Title = item.Title;
        this.WindowId = item.WindowId;
        this.Attention = item.Attention;
        this.Icon = item.Icon;
        this.OverlayIcon = item.OverlayIcon;
        this.ToolTip = item.ToolTip;
    }
    Activate(x: number = 0, y: number = 0) {
        return Activate(this.Service, x, y);
    }
    ContexMenu(x: number = 0, y: number = 0) {
        return ContextMenu(this.Service, x, y);
    }
    ProvideXdgActivationToken(token: string) {
        return ProvideXdgActivationToken(this.Service, token);
    }
    Scroll(delta: number, orientation: "horizontal" | "vertical") {
        return Scroll(this.Service, delta, orientation);
    }
    SecondaryActivate(x: number = 0, y: number = 0) {
        return SecondaryActivate(this.Service, x, y);
    }
}

export async function Items(): Promise<Item[]> {
    const result: Item[] = [];
    for (const item of await Items_()) {
        result.push(new Item(item));
    }
    return result;
}

export { Init, Stop } from "./bindings/github.com/HumXC/mikami/services/tray";

const listeners: ((items: Item[]) => void)[] = [];
export async function Subscribe(callback: (items: Item[]) => void) {
    if (id === 0) await WaitReady();
    if (listeners.length === 0) {
        tray.Subscribe(id);
        WailsEventOn("Tray.Update", async () => {
            const items = await Items();
            for (const listener of listeners) {
                listener(items);
            }
        });
    }

    listeners.push(callback);
}

export function Unsubscribe(callback: (items: Item[]) => void) {
    const index = listeners.indexOf(callback);
    if (index !== -1) listeners.splice(index, 1);
    if (listeners.length === 0) {
        tray.Unsubscribe(id);
        WailsEventOff(`Notifd.Notification`);
    }
}
