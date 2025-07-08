import call from "./call";
export function getEnv(key: string): Promise<string> {
    return call("os.getEnv", key);
}
export interface SystemInfo {
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

export interface UserInfo {
    name: string;
    home: string;
    shell: string;
    gecos: string;
    uid: number;
    gid: number;
    avatar: string | null;
}
export function getSystemInfo(): Promise<SystemInfo> {
    return call("os.getSystemInfo");
}
export function getUserInfo(): Promise<UserInfo> {
    return call("os.getUserInfo");
}
export function exec(argv: string[], needOutput: true): Promise<string>;
export function exec(argv: string[], needOutput?: false): Promise<void>;
export function exec(argv: string[], needOutput: boolean = false): Promise<string | void> {
    return call("os.exec", argv, needOutput);
}
