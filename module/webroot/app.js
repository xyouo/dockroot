import { exec, toast } from "./kernelsu.js";

const list = document.querySelector("#containers");
const notice = document.querySelector("#notice");
const refreshButton = document.querySelector("#refresh");

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
refreshButton.addEventListener("click", () => void refresh());

void refresh();
