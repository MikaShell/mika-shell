import { List as List_, Run } from "./bindings/github.com/HumXC/mikami/services/app";
import { Entry } from "./bindings/github.com/HumXC/mikami/services/models";
export class Application extends Entry {
    public Run(action: string = "", urls: string[] = []) {
        Run(this, action, urls);
    }
}
export async function List() {
    return (await List_()!).map((item) => new Application(item!));
}
