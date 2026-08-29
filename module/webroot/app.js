import { exec, toast } from "./kernelsu.js";

const list = document.querySelector("#containers");
const notice = document.querySelector("#notice");
const refreshButton = document.querySelector("#refresh");
const wakeStatus = document.querySelector("#wake-status");
const wakeDetail = document.querySelector("#wake-detail");
const wakeActions = document.querySelector("#wake-actions");

const labels = {
  healthy: ["运行正常", "ok"],
  unhealthy: ["运行异常", "warn"],
  stopped: ["已停止", "off"],
};

function escapeHtml(value) {
  return value.replace(/[&<>'"]/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[char]);
}

function parseRows(output) {
  return output.trim().split("\n").filter(Boolean).map((line) => {
    const [name = "", state = "stopped", localUrl = "", lanUrl = "", autostart = "0"] = line.split("\t");
    return { name, state, localUrl, lanUrl, autostart: autostart === "1" };
  });
}

function parseValues(output) {
  return Object.fromEntries(output.trim().split("\n").filter(Boolean).map((line) => {
    const separator = line.indexOf("=");
    return separator < 0 ? [line, ""] : [line.slice(0, separator), line.slice(separator + 1)];
  }));
}

function renderWake(values) {
  const mode = values.mode || "off";
  const labelsByMode = {
    scheduled: ["定时短唤醒", "ok"],
    continuous: ["全天唤醒", "warn"],
    off: ["已关闭", "off"],
  };
  const [label, stateClass] = labelsByMode[mode] || labelsByMode.off;
  wakeStatus.className = `status ${stateClass}`;
  wakeStatus.innerHTML = `<i></i>${label}`;
  if (mode === "scheduled") {
    const nextEpoch = Number(values.next_epoch || 0);
    const next = nextEpoch ? new Date(nextEpoch * 1000).toLocaleString() : "正在计算";
    wakeDetail.textContent = `等待期间允许深度休眠；下一次唤醒：${next}`;
  } else if (mode === "continuous") {
    wakeDetail.textContent = "CPU 将持续保持唤醒，定时最稳定，但会明显增加待机耗电。";
  } else {
    wakeDetail.textContent = "未主动唤醒 CPU，设备休眠时任务可能延迟。";
  }
  wakeActions.querySelectorAll("button").forEach((button) => {
    button.disabled = button.dataset.wake === mode;
  });
}

function addressRow(label, url, kind) {
  if (!url) return "";
  const safeUrl = escapeHtml(url);
  return `<div class="address-row">
    <div class="address-text"><span>${label}</span><code>${safeUrl}</code></div>
    <div class="address-actions">
      <button class="primary" data-open="${safeUrl}" type="button">打开</button>
      <button data-copy="${safeUrl}" type="button">复制${kind}</button>
    </div>
  </div>`;
}

function render(rows) {
  if (!rows.length) {
    list.innerHTML = '<div class="loading">暂无 Stack 配置。</div>';
    return;
  }
  list.innerHTML = rows.map(({ name, state, localUrl, lanUrl, autostart }) => {
    const [stateLabel, stateClass] = labels[state] || labels.stopped;
    const safeName = escapeHtml(name);
    const isStopped = state === "stopped";
    const addresses = localUrl
      ? `${addressRow("本机", localUrl, "本机地址")}${addressRow("局域网", lanUrl, "局域网地址")}`
      : '<span class="no-url">未配置 HEALTH_URL</span>';
    return `<article class="card">
      <div class="card-title">
        <h2>${safeName}</h2>
        <span class="status ${stateClass}"><i></i>${stateLabel}</span>
      </div>
      <div class="addresses">${addresses}</div>
      <div class="actions">
        <button data-up="${safeName}" ${isStopped ? "" : "disabled"} type="button">启动</button>
        <button data-down="${safeName}" ${isStopped ? "disabled" : ""} type="button">停止</button>
        <button data-restart="${safeName}" ${isStopped ? "disabled" : ""} type="button">重启</button>
        <button data-update="${safeName}" type="button">更新</button>
        <button data-autostart="${safeName}" data-enabled="${autostart ? "1" : "0"}" type="button">自启${autostart ? "开" : "关"}</button>
      </div>
    </article>`;
  }).join("");
}

async function toggleAutostart(name, enabled, button) {
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    toast("容器名称无效");
    return;
  }
  const turnOn = !enabled;
  const oldText = button.textContent;
  button.disabled = true;
  button.textContent = "设置中…";
  notice.hidden = true;
  try {
    const result = await exec(`/data/adb/modules/dockroot/bin/drctl autostart set ${name} ${turnOn ? "on" : "off"}`);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || "设置失败");
    toast(`已${turnOn ? "开启" : "关闭"} ${name} 的开机自启；当前运行状态不变`);
    await refresh();
  } catch (error) {
    notice.textContent = error instanceof Error ? error.message : String(error);
    notice.hidden = false;
    button.disabled = false;
    button.textContent = oldText;
  }
}

async function updateStack(name, button) {
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    toast("容器名称无效");
    return;
  }
  if (!window.confirm(`确定更新容器“${name}”吗？\n会先下载新镜像，再短暂停止服务进行替换；验证失败会自动回滚。`)) return;

  const oldText = button.textContent;
  let updated = false;
  button.disabled = true;
  button.textContent = "更新中…";
  notice.hidden = true;
  try {
    const result = await exec(`/data/adb/modules/dockroot/bin/drctl update ${name}`);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || "更新失败");
    updated = true;
    toast(`${name} 已更新`);
  } catch (error) {
    notice.textContent = error instanceof Error ? error.message : String(error);
    notice.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = oldText;
    if (updated) await refresh();
  }
}

async function restartStack(name, button) {
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    toast("容器名称无效");
    return;
  }
  if (!window.confirm(`确定重启容器“${name}”吗？\n正在执行的任务或传输会被中断。`)) return;

  const oldText = button.textContent;
  let restarted = false;
  button.disabled = true;
  button.textContent = "重启中…";
  notice.hidden = true;
  try {
    const result = await exec(`/data/adb/modules/dockroot/bin/drctl restart ${name}`);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || "重启失败");
    restarted = true;
    toast(`${name} 已重启`);
  } catch (error) {
    notice.textContent = error instanceof Error ? error.message : String(error);
    notice.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = oldText;
    if (restarted) await refresh();
  }
}

async function upStack(name, button) {
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    toast("容器名称无效");
    return;
  }
  const oldText = button.textContent;
  let started = false;
  button.disabled = true;
  button.textContent = "启动中…";
  notice.hidden = true;
  try {
    const result = await exec(`/data/adb/modules/dockroot/bin/drctl up ${name}`);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || "启动失败");
    started = true;
    toast(`${name} 已启动`);
  } catch (error) {
    notice.textContent = error instanceof Error ? error.message : String(error);
    notice.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = oldText;
    if (started) await refresh();
  }
}

async function downStack(name, button) {
  if (!/^[a-zA-Z0-9._-]+$/.test(name)) {
    toast("容器名称无效");
    return;
  }
  if (!window.confirm(`确定停止容器“${name}”吗？\n正在执行的任务或传输会被中断。`)) return;

  const oldText = button.textContent;
  let stopped = false;
  button.disabled = true;
  button.textContent = "停止中…";
  notice.hidden = true;
  try {
    const result = await exec(`/data/adb/modules/dockroot/bin/drctl down ${name}`);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || "停止失败");
    stopped = true;
    toast(`${name} 已停止`);
  } catch (error) {
    notice.textContent = error instanceof Error ? error.message : String(error);
    notice.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = oldText;
    if (stopped) await refresh();
  }
}

async function copyText(value) {
  try {
    await navigator.clipboard.writeText(value);
  } catch {
    const input = document.createElement("textarea");
    input.value = value;
    document.body.appendChild(input);
    input.select();
    document.execCommand("copy");
    input.remove();
  }
  toast("地址已复制");
}

async function refreshWake() {
  try {
    const result = await exec("/data/adb/modules/dockroot/bin/drctl wakelock status");
    if (result.errno !== 0) throw new Error(result.stderr || "唤醒状态读取失败");
    renderWake(parseValues(result.stdout));
  } catch (error) {
    wakeStatus.className = "status warn";
    wakeStatus.innerHTML = "<i></i>读取失败";
    wakeDetail.textContent = error instanceof Error ? error.message : String(error);
  }
}

async function setWakeMode(mode, button) {
  if (mode === "on" && !window.confirm("全天唤醒会明显增加待机耗电，确定继续吗？")) return;
  const oldText = button.textContent;
  button.disabled = true;
  button.textContent = "设置中…";
  try {
    const result = await exec(`/data/adb/modules/dockroot/bin/drctl wakelock ${mode}`);
    if (result.errno !== 0) throw new Error(result.stderr || result.stdout || "设置失败");
    toast("唤醒模式已更新");
  } catch (error) {
    notice.textContent = error instanceof Error ? error.message : String(error);
    notice.hidden = false;
  } finally {
    button.textContent = oldText;
    await refreshWake();
  }
}

async function refresh() {
  refreshButton.disabled = true;
  refreshButton.textContent = "刷新中…";
  notice.hidden = true;
  try {
    const result = await exec("/data/adb/modules/dockroot/bin/drctl web-status");
    if (result.errno !== 0) throw new Error(result.stderr || "状态读取失败");
    render(parseRows(result.stdout));
  } catch (error) {
    notice.textContent = error instanceof Error ? error.message : String(error);
    notice.hidden = false;
    list.innerHTML = '<div class="loading">无法读取容器状态。</div>';
  } finally {
    refreshButton.disabled = false;
    refreshButton.textContent = "刷新";
  }
}

list.addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  if (button.dataset.copy) void copyText(button.dataset.copy);
  if (button.dataset.open) window.location.href = button.dataset.open;
  if (button.dataset.autostart) void toggleAutostart(button.dataset.autostart, button.dataset.enabled === "1", button);
  if (button.dataset.update) void updateStack(button.dataset.update, button);
  if (button.dataset.restart) void restartStack(button.dataset.restart, button);
  if (button.dataset.up) void upStack(button.dataset.up, button);
  if (button.dataset.down) void downStack(button.dataset.down, button);
});
refreshButton.addEventListener("click", () => void Promise.all([refresh(), refreshWake()]));
wakeActions.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-wake]");
  if (button) void setWakeMode(button.dataset.wake, button);
});

void Promise.all([refresh(), refreshWake()]);