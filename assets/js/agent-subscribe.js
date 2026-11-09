(function () {
  document.querySelectorAll("[data-agent-subscribe]").forEach(function (shell) {
    var button = shell.querySelector("[data-agent-copy]");
    var label = shell.querySelector("[data-agent-copy-label]");
    var prompt = shell.querySelector("[data-agent-prompt]");
    var details = shell.querySelector("[data-agent-details]");
    var status = shell.querySelector("[data-agent-status]");
    var toast = shell.querySelector("[data-agent-toast]");
    var resetTimer;

    button.hidden = false;
    details.hidden = true;
    button.addEventListener("click", async function () {
      window.clearTimeout(resetTimer);
      toast.hidden = true;
      status.textContent = "";
      status.classList.add("sr-only");
      button.disabled = true;
      label.textContent = "正在复制…";

      try {
        await navigator.clipboard.writeText(prompt.value.trim());
        label.textContent = "已复制 ✓";
        details.hidden = true;
        toast.hidden = false;
      } catch (error) {
        label.textContent = "复制订阅指令";
        details.hidden = false;
        details.open = true;
        prompt.focus();
        prompt.select();
        prompt.setSelectionRange(0, prompt.value.length);
        status.textContent = "复制未完成，请手动复制下方的一句话。";
        status.classList.remove("sr-only");
      } finally {
        button.disabled = false;
      }

      resetTimer = window.setTimeout(function () {
        label.textContent = "复制订阅指令";
        toast.hidden = true;
      }, 5500);
    });
  });
})();
