// Adapted from KernelSU/js/index.js (Apache-2.0).
let callbackCounter = 0;

function callbackName(prefix) {
  return `${prefix}_callback_${Date.now()}_${callbackCounter++}`;
}

export function exec(command, options = {}) {
  return new Promise((resolve, reject) => {
    const name = callbackName("exec");
    const cleanup = () => { delete window[name]; };
    window[name] = (errno, stdout, stderr) => {
      resolve({ errno, stdout, stderr });
      cleanup();
    };
    try {
      globalThis.ksu.exec(command, JSON.stringify(options), name);
    } catch (error) {
      cleanup();
      reject(error);
    }
  });
}

export function toast(message) {
  globalThis.ksu.toast(message);
}
