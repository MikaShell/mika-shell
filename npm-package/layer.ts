import * as bindings from "./bindings/github.com/HumXC/mikami/services/index";
import {
    EdgeFlags,
    KeyboardMode,
    LayerFlags,
} from "./bindings/github.com/HumXC/mikami/layershell/models";
import { id, WaitReady } from "./common";

export type Edge = "top" | "bottom" | "left" | "right" | "none";
export type Layer = "top" | "bottom" | "overlay" | "background";
export class Options {
    Title: string;
    Namespace: string;
    AutoExclusiveZoneEnable: boolean;
    ExclusiveZone: number = -1;
    Anchor: Edge[];
    Margin: number[];
    Width: number;
    Height: number;
    Layer: Layer = "background";
    KeyboardMode: "none" | "exclusive" | "on-demand" = "none";
    Hidden: boolean = false;
    _toBindings(): bindings.LayerOptions {
        let opt = new bindings.LayerOptions();
        opt.Title = this.Title;
        opt.Namespace = this.Namespace;
        opt.AutoExclusiveZoneEnable = this.AutoExclusiveZoneEnable;
        opt.ExclusiveZone = this.ExclusiveZone;
        opt.Margin = this.Margin;
        opt.Width = this.Width;
        opt.Height = this.Height;
        switch (this.KeyboardMode) {
            case "none":
                opt.KeyboardMode = KeyboardMode.KEYBOARD_MODE_NONE;
                break;
            case "exclusive":
                opt.KeyboardMode = KeyboardMode.KEYBOARD_MODE_EXCLUSIVE;
                break;
            case "on-demand":
                opt.KeyboardMode = KeyboardMode.KEYBOARD_MODE_ON_DEMAND;
                break;
            default:
                break;
        }
        switch (this.Layer) {
            case "top":
                opt.Layer = LayerFlags.LAYER_TOP;
                break;
            case "bottom":
                opt.Layer = LayerFlags.LAYER_BOTTOM;
                break;
            case "overlay":
                opt.Layer = LayerFlags.LAYER_OVERLAY;
                break;
            case "background":
                opt.Layer = LayerFlags.LAYER_BACKGROUND;
                break;
            default:
                break;
        }
        opt.Anchor = ConvertEdge(this.Anchor);
        return opt;
    }
    constructor(props: Partial<Options> = {}) {
        if (props.Title) this.Title = props.Title;
        if (props.Namespace) this.Namespace = props.Namespace;
        if (props.AutoExclusiveZoneEnable)
            this.AutoExclusiveZoneEnable = props.AutoExclusiveZoneEnable;
        if (props.ExclusiveZone) this.ExclusiveZone = props.ExclusiveZone;
        if (props.Margin) this.Margin = props.Margin;
        if (props.Anchor) this.Anchor = props.Anchor;
        if (props.Width) this.Width = props.Width;
        if (props.Height) this.Height = props.Height;
        if (props.Layer) this.Layer = props.Layer;
        if (props.KeyboardMode) this.KeyboardMode = props.KeyboardMode;
        if (props.Hidden) this.Hidden = props.Hidden;
    }
}
function ConvertEdge(edges: Edge[]): EdgeFlags[] {
    const result = edges
        .map((edge) => {
            switch (edge) {
                case "top":
                    return EdgeFlags.EDGE_TOP;
                case "right":
                    return EdgeFlags.EDGE_RIGHT;
                case "bottom":
                    return EdgeFlags.EDGE_BOTTOM;
                case "left":
                    return EdgeFlags.EDGE_LEFT;
            }
        })
        .filter((v) => v !== undefined);
    return result;
}
export async function Init(options: Partial<Options> = {}) {
    if (id === 0) await WaitReady();
    const opt = new Options(options);
    return bindings.Layer.Init(id, opt._toBindings());
}
export async function OpenDevTools() {
    if (id === 0) await WaitReady();
    return bindings.Mikami.OpenDevTools(id);
}
export function SetLayer(layer: Layer) {
    let flag: LayerFlags;
    switch (layer) {
        case "top":
            flag = LayerFlags.LAYER_TOP;
            break;
        case "bottom":
            flag = LayerFlags.LAYER_BOTTOM;
            break;
        case "overlay":
            flag = LayerFlags.LAYER_OVERLAY;
            break;
        case "background":
            flag = LayerFlags.LAYER_BACKGROUND;
            break;
        default:
            throw new Error("");
    }
    return bindings.Layer.SetLayer(id, flag);
}
export function Show() {
    return bindings.Layer.Show(id);
}
// FIXME: ** (mikami:127234): CRITICAL **: 11:42:26.853: void webkitWebViewEvaluateJavascriptInternal(WebKitWebView *, const char *, gssize, const char *, const char *, RunJavascriptReturnType, GCancellable *, GAsyncReadyCallback, gpointer): assertion 'WEBKIT_IS_WEB_VIEW(webView)' failed
export function Close() {
    return bindings.Layer.Close(id);
}
export function Hide() {
    return bindings.Layer.Hide(id);
}
export function Size() {
    return bindings.Layer.Size(id);
}
export function SetSize(width: number, height: number) {
    return bindings.Layer.SetSize(id, width, height);
}
export function SetAnchor(...edge: Edge[]) {
    if (edge.find((e) => e === "none")) {
        return bindings.Layer.ResetAnchor(id);
    }
    return bindings.Layer.SetAnchor(id, ConvertEdge(edge), true);
}
export function SetExclusiveZone(zone: number) {
    return bindings.Layer.SetExclusiveZone(id, zone);
}
export function SetMargin(edge: Edge, margin: number) {
    return bindings.Layer.SetMargin(id, ConvertEdge([edge])[0], margin);
}
export function SetNamespace(namespace: string) {
    return bindings.Layer.SetNamespace(id, namespace);
}
export function AutoExclusiveZoneEnable() {
    return bindings.Layer.AutoExclusiveZoneEnable(id);
}
export function SetTitle(title: string) {
    return bindings.Layer.SetTitle(id, title);
}
export function SetKeyboardMode(mode: "none" | "exclusive" | "on-demand") {
    var kbMode = KeyboardMode.KEYBOARD_MODE_NONE;
    switch (mode) {
        case "none":
            kbMode = KeyboardMode.KEYBOARD_MODE_NONE;
            break;
        case "exclusive":
            kbMode = KeyboardMode.KEYBOARD_MODE_EXCLUSIVE;
            break;
        case "on-demand":
            kbMode = KeyboardMode.KEYBOARD_MODE_ON_DEMAND;
            break;
        default:
            break;
    }
    return bindings.Layer.SetKeyboardMode(id, kbMode);
}
