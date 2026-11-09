// Copy buttons for the commands on the setup page.
document.addEventListener("DOMContentLoaded", function () {
  var root = document.documentElement;
  var idle = root.getAttribute("data-copy") || "Copy";
  var done = root.getAttribute("data-copied") || "Copied";
  var svg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">';
  var ICON_COPY = svg + '<rect x="8.5" y="8.5" width="11" height="11" rx="2.2"/><path d="M15.5 8.5V6.7a2.2 2.2 0 0 0-2.2-2.2H6.7a2.2 2.2 0 0 0-2.2 2.2v6.6a2.2 2.2 0 0 0 2.2 2.2h1.8"/></svg>';
  var ICON_DONE = svg + '<path d="m5 12.5 4.5 4.5L19 7.5"/></svg>';

  // The Clipboard API needs HTTPS; the selection fallback also works without it and is
  // also tried when the browser denies the API.
  function copy(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).catch(function () { return copyBySelection(text); });
    }
    return copyBySelection(text);
  }

  function copyBySelection(text) {
    return new Promise(function (resolve, reject) {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      var ok = false;
      try {
        area.select();
        area.setSelectionRange(0, text.length);
        ok = document.execCommand("copy");
      } catch (e) {
        ok = false;
      } finally {
        document.body.removeChild(area);
      }
      if (ok) resolve(); else reject();
    });
  }

  document.querySelectorAll("pre > code").forEach(function (code) {
    var pre = code.parentNode;
    var button = document.createElement("button");
    button.type = "button";
    button.className = "copy-code";
    button.setAttribute("aria-label", idle);
    button.title = idle;
    button.innerHTML = ICON_COPY;
    button.addEventListener("click", function () {
      copy(code.textContent.trim() + "\n").then(function () {
        button.innerHTML = ICON_DONE;
        button.setAttribute("aria-label", done);
        button.title = done;
        button.classList.add("done");
        clearTimeout(button.reset);
        button.reset = setTimeout(function () {
          button.title = idle;
          button.innerHTML = ICON_COPY;
          button.setAttribute("aria-label", idle);
          button.classList.remove("done");
        }, 2000);
      }, function () {});
    });
    // The button sits on a wrapper, not in the pre: the pre scrolls sideways on narrow
    // screens and would take the button along.
    var wrap = document.createElement("div");
    wrap.className = "copy-wrap";
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    pre.classList.add("has-copy");
    wrap.appendChild(button);
  });
});
