(function () {
  const lists = Array.from(document.querySelectorAll("[data-pagination-list]"));

  if (!lists.length) {
    return;
  }

  const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

  const buildPageSet = (currentPage, totalPages) => {
    if (totalPages <= 7) {
      return Array.from({ length: totalPages }, (_, index) => index + 1);
    }

    const pages = new Set([1, totalPages]);

    for (let page = currentPage - 1; page <= currentPage + 1; page += 1) {
      if (page > 1 && page < totalPages) {
        pages.add(page);
      }
    }

    const sorted = Array.from(pages).sort((a, b) => a - b);
    const result = [];

    sorted.forEach((page, index) => {
      if (index > 0 && page - sorted[index - 1] > 1) {
        result.push("ellipsis");
      }

      result.push(page);
    });

    return result;
  };

  const readPageFromUrl = (paramName, totalPages) => {
    if (!paramName) {
      return 1;
    }

    const params = new URLSearchParams(window.location.search);
    const rawValue = Number.parseInt(params.get(paramName), 10);

    if (!Number.isFinite(rawValue)) {
      return 1;
    }

    return clamp(rawValue, 1, totalPages);
  };

  const updateUrl = (paramName, page) => {
    if (!paramName || !window.history || !window.history.replaceState) {
      return;
    }

    const url = new URL(window.location.href);

    if (page <= 1) {
      url.searchParams.delete(paramName);
    } else {
      url.searchParams.set(paramName, String(page));
    }

    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
  };

  const createButton = (label, options) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = options.className || "pagination-button";
    button.textContent = label;

    if (options.disabled) {
      button.disabled = true;
    }

    if (options.current) {
      button.classList.add("is-active");
      button.setAttribute("aria-current", "page");
    }

    if (options.label) {
      button.setAttribute("aria-label", options.label);
    }

    button.addEventListener("click", () => {
      if (!options.disabled && typeof options.onClick === "function") {
        options.onClick();
      }
    });

    return button;
  };

  lists.forEach((list) => {
    const items = Array.from(list.querySelectorAll("[data-pagination-item]"));
    const control = list.nextElementSibling && list.nextElementSibling.matches("[data-pagination-control]")
      ? list.nextElementSibling
      : null;
    const pageSize = Number.parseInt(list.dataset.pageSize, 10) || 20;
    const totalPages = Math.ceil(items.length / pageSize);
    const paramName = list.dataset.paginationParam || "";

    if (!control || totalPages <= 1) {
      if (control) {
        control.hidden = true;
      }

      return;
    }

    let currentPage = readPageFromUrl(paramName, totalPages);

    const render = (shouldScroll) => {
      const start = (currentPage - 1) * pageSize;
      const end = start + pageSize;

      items.forEach((item, index) => {
        item.hidden = index < start || index >= end;
      });

      control.hidden = false;
      control.innerHTML = "";

      const status = document.createElement("span");
      status.className = "pagination-status";
      status.setAttribute("aria-live", "polite");
      status.textContent = `${start + 1}-${Math.min(end, items.length)} / ${items.length}`;

      const pages = document.createElement("span");
      pages.className = "pagination-pages";

      const goToPage = (page) => {
        currentPage = clamp(page, 1, totalPages);
        updateUrl(paramName, currentPage);
        render(true);
      };

      pages.appendChild(createButton("上一页", {
        disabled: currentPage === 1,
        label: "上一页",
        onClick: () => goToPage(currentPage - 1),
      }));

      buildPageSet(currentPage, totalPages).forEach((page) => {
        if (page === "ellipsis") {
          const ellipsis = document.createElement("span");
          ellipsis.className = "pagination-ellipsis";
          ellipsis.textContent = "...";
          pages.appendChild(ellipsis);
          return;
        }

        pages.appendChild(createButton(String(page), {
          current: page === currentPage,
          label: `第 ${page} 页`,
          onClick: () => goToPage(page),
        }));
      });

      pages.appendChild(createButton("下一页", {
        disabled: currentPage === totalPages,
        label: "下一页",
        onClick: () => goToPage(currentPage + 1),
      }));

      control.append(status, pages);

      if (shouldScroll) {
        const scrollTarget = list.closest(".home-list-section, .weekly-tab-panel") || list;
        scrollTarget.scrollIntoView({ block: "start", behavior: "smooth" });
      }
    };

    render(false);
  });
}());
