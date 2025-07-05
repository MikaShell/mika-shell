import call from "./call";
export function getEnv(key: string) {
    return call("os.getEnv", key);
}
