// Copies text for beta.js and copy.js. The Clipboard API needs HTTPS; the selection fallback
// also works without it and is tried when the browser denies the API. `host` is where the
// helper textarea goes, e.g. an open dialog, so the selection stays inside it.
window.copyText = function (text, host) {
  host = host || document.body;

  function bySelection() {
    var before = document.activeElement;
    return new Promise(function (resolve, reject) {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      host.appendChild(area);
      var ok = false;
      try {
        area.select();
        area.setSelectionRange(0, text.length);
        ok = document.execCommand("copy");
      } catch (e) {
        ok = false;
      } finally {
        host.removeChild(area);
        // Selecting moved the focus; the button that was pressed gets it back.
        if (before && before.focus) before.focus();
      }
      if (ok) resolve(); else reject();
    });
  }

  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text).catch(bySelection);
  }
  return bySelection();
};
