const postMessage = (msg) => {
    return window.webkit.messageHandlers.mikami.postMessage(msg);
};
/**
 * 加法函数
 * @param {string} method - 调用的函数名
 * @param {Array<any>} args - 参数
 * @returns {Promise<any>}
 */
export default function call(method, ...args) {
    return postMessage({
        method,
        args,
    });
}
