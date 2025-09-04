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
    base64Output: boolean;
};
export function getSystemInfo(): Promise<SystemInfo> {
    return call("os.getSystemInfo");
}
export function getUserInfo(): Promise<UserInfo> {
    return call("os.getUserInfo");
}
// 阻塞执行命令，进程退出时返回输出
// 重载签名
export function exec(argv: string[]): Promise<void>;
export function exec(argv: string[], output: "string" | "base64"): Promise<string>;
export function exec(argv: string[], output: "ignore"): Promise<void>;
export function exec(
    argv: string[],
    output: "string" | "base64" | "ignore" = "ignore",
    inheritStderr = false
): Promise<any> {
    return call("os.exec", argv, output, inheritStderr);
}
export function execAsync(argv: string[], inheritStderr = false): Promise<number> {
    return call("os.execAsync", argv, inheritStderr);
}
export function write(path: string, base64: string): Promise<void> {
    return call("os.write", path, base64);
}
export function read(path: string): Promise<string> {
    return call("os.read", path);
}
