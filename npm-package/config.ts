import { Read as Read_ } from "./bindings/github.com/HumXC/mikami/services/config";

export { Write } from "./bindings/github.com/HumXC/mikami/services/config";
export async function Read(): Promise<any> {
    try {
        return JSON.parse(await Read_());
    } catch (error) {
        console.log(error);
        return {};
    }
}
