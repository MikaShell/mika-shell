import * as bindings from "./bindings/github.com/HumXC/mikami/services/index";
import { EdgeFlags, LayerFlags } from "./bindings/github.com/HumXC/mikami/layershell/models";
import { id, WaitReady } from "./init";

export enum Edge {
    None = 0,
    Top = 1,
    Right = 2,
    Bottom = 4,
    Left = 8,
}
export enum Layer {
    Background = 0,
    Bottom = 1,
    Top = 2,
    Overlay = 3,
}
export class Options {
    Title: string;
    Namespace: string;
    AutoExclusiveZoneEnable: boolean;
    ExclusiveZone: number = -1;
    Anchor: Edge;
    Margin: number[];
    Width: number;
    Height: number;
    Layer: Layer = Layer.Background;
    _toBindings(): bindings.LayerOptions {
        let opt = new bindings.LayerOptions();
        opt.Title = this.Title;
        opt.Namespace = this.Namespace;
        opt.AutoExclusiveZoneEnable = this.AutoExclusiveZoneEnable;
        opt.ExclusiveZone = this.ExclusiveZone;
        opt.Margin = this.Margin;
        opt.Width = this.Width;
        opt.Height = this.Height;
        opt.Layer = this.Layer as unknown as LayerFlags;
        if (this.Anchor & Edge.Top) {
            opt.Anchor.push(EdgeFlags.EDGE_TOP);
        }
        if (this.Anchor & Edge.Right) {
            opt.Anchor.push(EdgeFlags.EDGE_RIGHT);
        }
        if (this.Anchor & Edge.Bottom) {
            opt.Anchor.push(EdgeFlags.EDGE_BOTTOM);
        }
        if (this.Anchor & Edge.Left) {
            opt.Anchor.push(EdgeFlags.EDGE_LEFT);
        }
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
    }
}
function ConvertEdge(edge: Edge): EdgeFlags {
    switch (edge) {
        case Edge.Top:
            return EdgeFlags.EDGE_TOP;
        case Edge.Right:
            return EdgeFlags.EDGE_RIGHT;
        case Edge.Bottom:
            return EdgeFlags.EDGE_BOTTOM;
        case Edge.Left:
            return EdgeFlags.EDGE_LEFT;
        default:
            return EdgeFlags.EDGE_LEFT;
    }
}
export async function Init(options: Options = new Options()) {
    if (id === 0) await WaitReady();
    return bindings.Layer.Init(id, options._toBindings());
}
export function SetLayer(layer: Layer) {
    return bindings.Layer.SetLayer(id, layer as unknown as LayerFlags);
}
export function Show() {
    return bindings.Layer.Show(id);
}
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
export function SetAnchor(edge: Edge) {
    if (edge === Edge.None) {
        return bindings.Layer.ResetAnchor(id);
    }
    return bindings.Layer.SetAnchor(id, ConvertEdge(edge), true);
}
export function SetExclusiveZone(zone: number) {
    return bindings.Layer.SetExclusiveZone(id, zone);
}
export function SetMargin(edge: Edge, margin: number) {
    return bindings.Layer.SetMargin(id, ConvertEdge(edge), margin);
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
