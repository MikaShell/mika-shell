import * as bindings from "./bindings/github.com/HumXC/mikami/services/index";
import { id, WaitReady } from "./common";

class Options {
    Title: string;
    Width: number;
    Height: number;
    MaxWidth: number;
    MaxHeight: number;
    MinWidth: number;
    MinHeight: number;
    constructor(props: Partial<Options> = {}) {
        if (props.Title) this.Title = props.Title;
        if (props.Width) this.Width = props.Width;
        if (props.Height) this.Height = props.Height;
        if (props.MaxWidth) this.MaxWidth = props.MaxWidth;
        if (props.MaxHeight) this.MaxHeight = props.MaxHeight;
        if (props.MinWidth) this.MinWidth = props.MinWidth;
        if (props.MinHeight) this.MinHeight = props.MinHeight;
    }
}
export async function Init(options: Options = new Options()) {
    if (id === 0) await WaitReady();
    return bindings.Window.Init(id, options);
}
export function Show() {
    return bindings.Window.Show(id);
}
export function Close() {
    return bindings.Window.Close(id);
}
export function Hide() {
    return bindings.Window.Hide(id);
}
export function SetTitle(title: string) {
    return bindings.Window.SetTitle(id, title);
}
export function SetMinSize(width: number, height: number) {
    return bindings.Window.SetMinSize(id, width, height);
}
export function SetMaxSize(width: number, height: number) {
    return bindings.Window.SetMaxSize(id, width, height);
}
