// @ts-ignore
import { Events } from "@wailsio/runtime";

const tasks: Function[] = [];

export let id: number = 0;
export let name: string = "";
Events.On("MikamiReady", () => {
    id = Number(sessionStorage.getItem("mikami_id"));
    name = sessionStorage.getItem("mikami_name")!;
    while (true) {
        const t = tasks.pop();
        if (t) t();
        else break;
    }
});
export function WaitReady(): Promise<void> {
    return new Promise((resolve, reject) => tasks.push(resolve));
}

type Event = {
    name: string;
    data: any;
    sender?: string;
};

export function WailsEventOn(
    eventName: string,
    callback: (event: { name: string; data: any }) => void
) {
    Events.On(eventName, (e: Event) => {
        if (e.sender !== name) return;
        callback({ name: e.name, data: e.data });
    });
}

export function WailsEventOff(eventName: string) {
    Events.Off(eventName);
}
