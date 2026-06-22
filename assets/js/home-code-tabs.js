(function () {
  function activateTab(shell, key) {
    shell.querySelectorAll("[data-code-tab]").forEach(function (tab) {
      var isActive = tab.getAttribute("data-code-tab") === key;
      tab.classList.toggle("is-active", isActive);
      tab.setAttribute("aria-selected", isActive ? "true" : "false");
    });

    shell.querySelectorAll("[data-code-panel]").forEach(function (panel) {
      panel.hidden = panel.getAttribute("data-code-panel") !== key;
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll(".home-code-demo").forEach(function (shell) {
      shell.querySelectorAll("[data-code-tab]").forEach(function (tab) {
        tab.addEventListener("click", function () {
          activateTab(shell, tab.getAttribute("data-code-tab"));
        });
      });
    });
  });
})();
