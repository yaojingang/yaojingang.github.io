(function () {
  document.querySelectorAll("[data-agent-subscribe]").forEach(function (shell) {
    var button = shell.querySelector("[data-agent-copy]");
    var label = shell.querySelector("[data-agent-copy-label]");
    var prompt = shell.querySelector("[data-agent-prompt]");
    var details = shell.querySelector("[data-agent-details]");
    var status = shell.querySelector("[data-agent-status]");
    var resetTimer;

    button.hidden = false;
    button.addEventListener("click", async function () {
      window.clearTimeout(resetTimer);
      button.disabled = true;
      label.textContent = "正在复制…";

      try {
        await navigator.clipboard.writeText(prompt.value.trim());
        label.textContent = "已复制 ✓";
        status.textContent = "粘贴到你的 AI 工作台，创建每周提醒。";
      } catch (error) {
        label.textContent = "复制订阅指令";
        details.open = true;
        prompt.focus();
        prompt.select();
        prompt.setSelectionRange(0, prompt.value.length);
        status.textContent = "复制未完成，请手动复制上方指令。";
      } finally {
        button.disabled = false;
      }

      resetTimer = window.setTimeout(function () {
        label.textContent = "复制订阅指令";
      }, 2400);
    });
  });
})();
