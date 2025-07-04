import call from "./call.js";
/**
 *
 * @param {number} name
 * @param {number} size
 * @param {number} scale
 * @returns {Promise<string>}
 */
function lookup(name, size, scale = 1) {
    return call("icon.lookup", name, size, scale);
}
export { lookup };
