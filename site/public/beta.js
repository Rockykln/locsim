// Dialogs with a form that prepares an email: the beta request and the problem report.
// Nothing is sent from the page; the email opens in the visitor's own mail app.
document.addEventListener("DOMContentLoaded", function () {
  var root = document.documentElement;

  // The Clipboard API needs HTTPS; the selection fallback also works without it.
  function copyText(text, host) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).catch(function () { return copyBySelection(text, host); });
    }
    return copyBySelection(text, host);
  }

  function copyBySelection(text, host) {
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
        if (before && before.focus) before.focus();
      }
      if (ok) resolve(); else reject();
    });
  }

  function setup(dialog) {
    var form = dialog.querySelector("form");
    var mail = dialog.querySelector("[data-mail]");
    var copy = dialog.querySelector("[data-copy]");
    var start = dialog.getAttribute("data-start") || "form";
    var longNote = dialog.querySelector("[data-long]");
    var body = "";
    var tooLong = false;

    function show(step, noFocus) {
      dialog.querySelectorAll("[data-step]").forEach(function (section) {
        section.hidden = section.getAttribute("data-step") !== step;
      });
      // The dialog is named after the visible step.
      var title = dialog.querySelector('[data-step="' + step + '"] h2');
      if (title) {
        if (!title.id) title.id = dialog.id + "-" + step + "-title";
        dialog.setAttribute("aria-labelledby", title.id);
      }
      if (!noFocus && title) title.focus();
    }

    // When the keyboard opens, iOS moves the visible area but leaves fixed elements where they
    // were, so the page shows below the form. The form follows the visible area instead.
    var viewport = window.visualViewport;
    function fit() {
      if (!viewport) return;
      // The keyboard is translucent: the form also covers the area behind it, with room at
      // the end so the last fields can still be scrolled above it.
      // While pinch-zoomed the visible area is small without any keyboard.
      var keyboard = Math.abs(viewport.scale - 1) < 0.01 ? Math.max(0, window.innerHeight - viewport.height) : 0;
      dialog.style.setProperty("--vv-top", viewport.offsetTop + "px");
      dialog.style.setProperty("--vv-height", (viewport.height + keyboard) + "px");
      dialog.style.setProperty("--vv-keyboard", keyboard + "px");
    }

    // The page behind the dialog must not scroll, also not on iOS.
    function open() {
      if (dialog.open) return;
      show(start, true);
      fit();
      dialog.showModal();
      root.classList.add("dialog-open");
      if (viewport) {
        viewport.addEventListener("resize", fit);
        viewport.addEventListener("scroll", fit);
      }
      show(start);
    }
    dialog.addEventListener("close", function () {
      root.classList.remove("dialog-open");
      // Otherwise a reload of a #beta link opens the dialog again.
      if (location.hash === "#" + dialog.id) {
        history.replaceState(null, "", location.pathname + location.search);
      }
      if (viewport) {
        viewport.removeEventListener("resize", fit);
        viewport.removeEventListener("scroll", fit);
      }
    });

    var trigger = '[data-open="' + dialog.id + '"]' + (dialog.id === "beta" ? ", [data-beta]" : "");
    document.querySelectorAll(trigger).forEach(function (link) {
      link.addEventListener("click", function (event) {
        // Cmd/Ctrl/Shift-click and middle click follow the link, e.g. into a new tab.
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button) return;
        event.preventDefault();
        open();
      });
    });
    // Links such as locsim.rockykln.com/#beta open it directly.
    if (location.hash === "#" + dialog.id) open();

    // On phones the dialog fills the screen, so a tap on its empty area also lands on the
    // dialog element. Only a press and release outside its box count as a backdrop click;
    // a drag that starts in a field and ends outside does not.
    function outside(event) {
      var box = dialog.getBoundingClientRect();
      return event.clientX < box.left || event.clientX > box.right ||
        event.clientY < box.top || event.clientY > box.bottom;
    }
    var pressedOutside = false;
    dialog.addEventListener("pointerdown", function (event) {
      pressedOutside = event.target === dialog && outside(event);
    });

    dialog.addEventListener("click", function (event) {
      var target = event.target.closest("[data-go], [data-close]");
      if (target && target.hasAttribute("data-close")) dialog.close();
      else if (target) {
        // Early Access and development builds share the form; the button sets title and email text.
        if (target.hasAttribute("data-subject")) {
          form.setAttribute("data-subject", target.getAttribute("data-subject"));
          form.setAttribute("data-intro", target.getAttribute("data-intro"));
          dialog.querySelector('[data-step="form"] h2').textContent = target.getAttribute("data-title");
        }
        show(target.getAttribute("data-go"));
      }
      else if (event.target === dialog && pressedOutside && outside(event)) dialog.close();
    });

    // Live count for fields with a limit.
    var counters = dialog.querySelectorAll("[data-count-for]");
    function count() {
      counters.forEach(function (counter) {
        var field = document.getElementById(counter.getAttribute("data-count-for"));
        counter.textContent = field.value.length + " / " + field.maxLength;
      });
    }
    form.addEventListener("input", count);
    form.addEventListener("reset", function () { setTimeout(count); });
    // Restored or autofilled fields send no input event.
    count();
    dialog.addEventListener("focusin", count, { once: true });

    // "Device:" but not "What did you do?:"; French puts a space before the colon.
    var colon = root.lang === "fr" ? "\u00a0:" : ":";
    function heading(label) {
      if (/[?:]$/.test(label)) return label;
      return label + colon;
    }

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (!form.reportValidity()) return;
      var lines = [form.getAttribute("data-intro"), ""];
      var checks = false;
      form.querySelectorAll("[data-label]").forEach(function (field) {
        var label = field.getAttribute("data-label");
        var value = field.value.trim();
        if (field.type === "checkbox") {
          if (!checks) lines.push("");
          checks = true;
          lines.push((field.checked ? "[x] " : "[ ] ") + label);
        } else if (field.tagName === "TEXTAREA") {
          // Longer answers start on their own line, so the email stays readable.
          lines.push("", heading(label), value || "-", "");
        } else {
          lines.push(heading(label) + " " + (value || "-"));
        }
      });
      lines.push("", form.getAttribute("data-outro"));
      body = lines.join("\n").replace(/\n{3,}/g, "\n\n");
      var subject = form.getAttribute("data-subject");
      var key = form.getAttribute("data-subject-field");
      if (key && form.elements[key].value.trim()) subject += colon + " " + form.elements[key].value.trim();
      // Mail links take line breaks as CRLF. Some mail apps cut links after about 2000
      // characters; a longer text is copied instead and the link only fills in the subject.
      var href = "mailto:" + form.getAttribute("data-to") + "?subject=" + encodeURIComponent(subject);
      var full = href + "&body=" + encodeURIComponent(body.replace(/\n/g, "\r\n"));
      tooLong = full.length > 1900;
      mail.href = tooLong ? href : full;
      if (longNote) longNote.hidden = !tooLong;
      var shown = dialog.querySelector("[data-email]");
      if (shown) shown.textContent = form.elements.email.value.trim();
      copy.textContent = copy.getAttribute("data-idle");
      show("done");
    });

    // Once the email is opened or copied, the request is done: the next visit starts empty.
    // The prepared text stays, so opening and copying both keep working on this step.
    // A text too long for the link is still needed for copying, so the form stays filled.
    mail.addEventListener("click", function () { if (!tooLong) form.reset(); });
    copy.addEventListener("click", function () {
      copyText(body, dialog).then(function () {
        copy.textContent = copy.getAttribute("data-done");
        if (!tooLong) form.reset();
      }, function () {
        copy.textContent = copy.getAttribute("data-idle");
      });
    });
  }

  document.querySelectorAll("dialog.beta-dialog").forEach(function (dialog) {
    if (typeof dialog.showModal === "function") setup(dialog);
  });
});
