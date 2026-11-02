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
  }

  apply(current);

  document.addEventListener("DOMContentLoaded", function () {
    apply(current);
    var button = document.querySelector(".theme-toggle");
    if (!button) return;
    var labels = JSON.parse(button.getAttribute("data-labels"));

    function render() {
      var label = labels.title + ": " + labels[current];
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
