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
    const [name = "", state = "stopped", url = ""] = line.split("\t");
    return { name, state, url };
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

function render(rows) {
  if (!rows.length) {
    list.innerHTML = '<div class="loading">暂无 Stack 配置。</div>';
    return;
  }
  list.innerHTML = rows.map(({ name, state, url }) => {
    const [stateLabel, stateClass] = labels[state] || labels.stopped;
    const safeName = escapeHtml(name);
    const safeUrl = escapeHtml(url);
    const addressActions = url
      ? `<button class="primary" data-open="${safeUrl}" type="button">打开</button>
         <button data-copy="${safeUrl}" type="button">复制地址</button>`
      : '<span class="no-url">未配置 HEALTH_URL</span>';
    const actions = `${addressActions}
      <button class="danger" data-restart="${safeName}" type="button">重启</button>`;
    return `<article class="card">
      <div class="card-title">
        <h2>${safeName}</h2>
        <span class="status ${stateClass}"><i></i>${stateLabel}</span>
      </div>
      <p class="url">${safeUrl || "无可打开地址"}</p>
      <div class="actions">${actions}</div>
    </article>`;
  }).join("");
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
  if (button.dataset.restart) void restartStack(button.dataset.restart, button);
});
refreshButton.addEventListener("click", () => void Promise.all([refresh(), refreshWake()]));
wakeActions.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-wake]");
  if (button) void setWakeMode(button.dataset.wake, button);
});

void Promise.all([refresh(), refreshWake()]);
