export default function call(method: string, ...args: any[]): Promise<any> {
    // @ts-ignore
    return window.webkit.messageHandlers.mikaShell.postMessage({
        method,
        args,
    });
}
