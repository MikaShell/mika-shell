import call from "./call";
export function getEnv(key: string): Promise<string> {
    return call("os.getEnv", key);
}
export interface Info {
    name: string;
    version: string;
    prettyName: string;
    logo: string;
    arch: string;
    uptime: number;
    kernel: string;
    cpu: string;
    hostname: string;
}
export function getInfo(): Promise<Info> {
    return call("os.getInfo");
}
export function exec(...argv: string[]): Promise<void> {
    return call("os.exec", argv);
}
export function execWithOutput(...argv: string[]): Promise<string> {
    return call("os.execWithOutput", argv);
}
