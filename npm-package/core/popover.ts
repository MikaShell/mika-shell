import call from "./call";
type Position = "top" | "bottom" | "left" | "right";

const PositionToNumber: Record<Position, number> = {
    left: 0,
    right: 1,
    top: 2,
    bottom: 3,
};
export type Options = {
    parent: number;
    hidden: boolean;
    width: number;
    height: number;
    offsetX: number;
    offsetY: number;
    autoHide: boolean;
    position: Position;
    positionTo: {
        x: number;
        y: number;
        w: number;
        h: number;
    };
    cascadePopdown: boolean;
    backgroundTransparent: boolean;
};

export function init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        parent: options.parent ?? 0,
        hidden: options.hidden ?? false,
        width: options.width ?? -1,
        height: options.height ?? -1,
        offsetX: options.offsetX ?? 0,
        offsetY: options.offsetY ?? 0,
        autoHide: options.autoHide ?? true,
        position: options.position !== undefined ? PositionToNumber[options.position] : 3,
        positionTo: options.positionTo ?? { x: 0, y: 0, w: -1, h: -1 },
        cascadePopdown: options.cascadePopdown ?? true,
        backgroundTransparent: options.backgroundTransparent ?? false,
    };
    return call("popover.init", opt);
}
export async function getSize(): Promise<{ width: number; height: number }> {
    return call("popover.getSize");
}
// 每一次更新, 无论 autoHide 是否为 true, 都会触发 `hide` 事件, 需要自己处理重新显示
// 如果是因为更新 size 导致的 `hide`, 那就不应该 close
export async function setSize(width: number, height: number): Promise<void> {
    return call("popover.setSize", width, height);
}
export async function getPosition(): Promise<Position> {
    const position = await call("popover.getPosition");
    switch (position) {
        case 0:
            return "left";
        case 1:
            return "right";
        case 2:
            return "top";
        case 3:
            return "bottom";
    }
    throw new Error("Unexpected position value:", position);
}
export async function setPosition(position: Position): Promise<void> {
    return call("popover.setPosition", PositionToNumber[position]);
}
export async function getOffset(): Promise<{ x: number; y: number }> {
    return call("popover.getOffset");
}
export async function setOffset(x: number, y: number): Promise<void> {
    return call("popover.setOffset", x, y);
}
export async function getPositionTo(): Promise<{ x: number; y: number; w: number; h: number }> {
    return call("popover.getPositionTo");
}
export async function setPositionTo(rect: {
    x: number;
    y: number;
    w: number;
    h: number;
}): Promise<void> {
    return call("popover.setPositionTo", rect.x, rect.y, rect.w, rect.h);
}
import * as layer from "./layer";
export const on = layer.on;
export const off = layer.off;
export const once = layer.once;
export const show = layer.show;
export const hide = layer.hide;
export const close = layer.close;
export const openDevTools = layer.openDevTools;
