// Theme: "auto" follows the system, otherwise "light" or "dark". Stored per browser.
(function () {
  var root = document.documentElement;
  var key = "locsim-theme";
  var order = ["auto", "light", "dark"];
  var colors = { light: "#fbfafd", dark: "#0e0d17" };

  function read() {
    var value;
    try { value = localStorage.getItem(key); } catch (e) { value = null; }
    return order.indexOf(value) === -1 ? "auto" : value;
  }

  var current = read();

  function apply(theme) {
    if (theme === "auto") root.removeAttribute("data-theme");
    else root.setAttribute("data-theme", theme);
    var metas = document.querySelectorAll('meta[name="theme-color"]');
    for (var i = 0; i < metas.length; i++) {
      var media = metas[i].getAttribute("media") || "";
      var system = media.indexOf("dark") !== -1 ? "dark" : "light";
      metas[i].setAttribute("content", colors[theme === "auto" ? system : theme]);
    }
    // Picture sources follow the system; a chosen theme overrides them, so only one variant loads.
    var sources = document.querySelectorAll("source[data-theme-source]");
    for (var j = 0; j < sources.length; j++) {
      sources[j].setAttribute("media", theme === "auto" ? "(prefers-color-scheme: dark)" : theme === "dark" ? "all" : "not all");
    }
  }

  apply(current);

  // Language menu: close on outside press or Escape. iOS Safari fires no click for taps on
  // plain text or background, so the press itself is used.
  document.addEventListener("pointerdown", function (event) {
    var menu = document.querySelector(".lang-menu[open]");
    if (menu && !menu.contains(event.target)) menu.removeAttribute("open");
  });
  document.addEventListener("keydown", function (event) {
    if (event.key !== "Escape") return;
    var menu = document.querySelector(".lang-menu[open]");
    if (!menu) return;
    menu.removeAttribute("open");
    menu.querySelector("summary").focus();
  });

  // Closed questions would print without their answers.
  window.addEventListener("beforeprint", function () {
    document.querySelectorAll("details:not([open])").forEach(function (item) {
      item.setAttribute("data-print-open", "");
      item.open = true;
    });
  });
  window.addEventListener("afterprint", function () {
    document.querySelectorAll("details[data-print-open]").forEach(function (item) {
      item.removeAttribute("data-print-open");
      item.open = false;
    });
  });

  document.addEventListener("DOMContentLoaded", function () {
    apply(current);
    var button = document.querySelector(".theme-toggle");
    if (!button) return;
    var labels = JSON.parse(button.getAttribute("data-labels"));

    function render() {
      var label = labels.title + (root.lang === "fr" ? "\u00a0: " : ": ") + labels[current];
      button.setAttribute("data-state", current);
      button.setAttribute("aria-label", label);
      button.setAttribute("title", label);
    }

    button.hidden = false;
    render();
    button.addEventListener("click", function () {
      current = order[(order.indexOf(current) + 1) % order.length];
      try { localStorage.setItem(key, current); } catch (e) {}
      apply(current);
      render();
    });
  });
})();
