import { id, WailsEventOff, WailsEventOn, WaitReady } from "./common";

export {
    GetNotification,
    GetNotifications,
} from "./bindings/github.com/HumXC/mikami/services/notifd";
import * as notifd from "./bindings/github.com/HumXC/mikami/services/notifd";

export { Notification } from "./bindings/github.com/HumXC/mikami/services/models";
import { Notification } from "./bindings/github.com/HumXC/mikami/services/models";

const onNotificationListener: ((n: Notification) => void)[] = [];
const onCloseNotificationListener: ((id: number) => void)[] = [];
export async function Subscribe<T extends "notification" | "close-notification">(
    name: T,
    callback: {
        ["notification"]: (n: Notification) => void;
        ["close-notification"]: (id: number) => void;
    }[T]
): Promise<void> {
    if (id === 0) await WaitReady();
    if (name === "notification") {
        if (onNotificationListener.length === 0) {
            notifd.Subscribe(id);
            WailsEventOn(`Notifd.Notification`, (e) => {
                const data = e.data[0];
                for (const listener of onNotificationListener || []) {
                    listener(data as Notification);
                }
            });
        }
        onNotificationListener.push(callback as (n: Notification) => void);
    }
    if (name === "close-notification") {
        if (onCloseNotificationListener.length === 0) {
            notifd.Subscribe(id);
            WailsEventOn(`Notifd.CloseNotification`, (e) => {
                const data = e.data[0];
                for (const listener of onCloseNotificationListener || []) {
                    listener(data as number);
                }
            });
        }
        onCloseNotificationListener.push(callback as (id: number) => void);
    }
}
export function Unsubscribe(callback: (n: Notification) => void): void {
    const index = onNotificationListener.indexOf(callback);
    if (index !== -1) onNotificationListener.splice(index, 1);
    if (onNotificationListener.length === 0) {
        notifd.Unsubscribe(id);
        WailsEventOff(`Notifd.Notification`);
    }
}
export function CloseNotification(id: number) {
    return notifd.CloseNotification(id);
}
export function InvokeAction(id: number, action: string) {
    return notifd.InvokeAction(id, action);
}
export function ActivationToken(id: number, token: string) {
    return notifd.ActivationToken(id, token);
}
