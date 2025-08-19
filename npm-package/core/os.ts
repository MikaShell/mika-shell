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
export type ExecOptions = {
    needOutput: boolean;
    block: boolean;
};
export function getSystemInfo(): Promise<SystemInfo> {
    return call("os.getSystemInfo");
}
export function getUserInfo(): Promise<UserInfo> {
    return call("os.getUserInfo");
}

export function exec(argv: string[], options: Partial<ExecOptions> = {}): Promise<string | void> {
    const opt: ExecOptions = {
        needOutput: options.needOutput ?? false,
        block: options.block ?? false,
    };
    return call("os.exec", argv, opt);
}
export function write(path: string, base64: string): Promise<void> {
    return call("os.write", path, base64);
}
export function read(path: string): Promise<string> {
    return call("os.read", path);
}
