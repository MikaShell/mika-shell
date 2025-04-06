// @ts-ignore
import { Events } from "@wailsio/runtime";

const tasks: Function[] = [];

export let id: number = 0;
Events.On("MikamiReady", () => {
    id = Number(sessionStorage.getItem("mikami_id"));
    while (true) {
        const t = tasks.pop();
        if (t) t();
        else break;
    }
});
export function WaitReady(): Promise<void> {
    return new Promise((resolve, reject) => tasks.push(resolve));
}
