// Dialogs with a form that prepares an email: the beta request and the problem report.
// Nothing is sent from the page; the email opens in the visitor's own mail app.
document.addEventListener("DOMContentLoaded", function () {
  var root = document.documentElement;

  // The Clipboard API needs HTTPS; the selection fallback also works without it.
  function copyText(text, host) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
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

    function show(step) {
      dialog.querySelectorAll("[data-step]").forEach(function (section) {
        section.hidden = section.getAttribute("data-step") !== step;
      });
      var title = dialog.querySelector('[data-step="' + step + '"] h2');
      if (title) title.focus();
    }

    // When the keyboard opens, iOS moves the visible area but leaves fixed elements where they
    // were, so the page shows below the form. The form follows the visible area instead.
    var viewport = window.visualViewport;
    function fit() {
      if (!viewport) return;
      // The keyboard is translucent: the form also covers the area behind it, with room at
      // the end so the last fields can still be scrolled above it.
      var keyboard = Math.max(0, window.innerHeight - viewport.height);
      dialog.style.setProperty("--vv-top", viewport.offsetTop + "px");
      dialog.style.setProperty("--vv-height", (viewport.height + keyboard) + "px");
      dialog.style.setProperty("--vv-keyboard", keyboard + "px");
    }

    // The page behind the dialog must not scroll, also not on iOS.
    function open() {
      show(start);
      root.classList.add("dialog-open");
      fit();
      if (viewport) {
        viewport.addEventListener("resize", fit);
        viewport.addEventListener("scroll", fit);
      }
      dialog.showModal();
    }
    dialog.addEventListener("close", function () {
      root.classList.remove("dialog-open");
      if (viewport) {
        viewport.removeEventListener("resize", fit);
        viewport.removeEventListener("scroll", fit);
      }
    });

    var trigger = '[data-open="' + dialog.id + '"]' + (dialog.id === "beta" ? ", [data-beta]" : "");
    document.querySelectorAll(trigger).forEach(function (link) {
      link.addEventListener("click", function (event) {
        event.preventDefault();
        open();
      });
    });
    // Links such as locsim.rockykln.com/#beta open it directly.
    if (location.hash === "#" + dialog.id) open();

    // A drag that starts in a field and ends on the backdrop is no click outside.
    var pressed = null;
    dialog.addEventListener("pointerdown", function (event) { pressed = event.target; });

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
      // A click on the backdrop lands on the dialog itself.
      else if (event.target === dialog && pressed === dialog) dialog.close();
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
    function heading(label) {
      if (/[?:]$/.test(label)) return label;
      return label + (root.lang === "fr" ? "\u00a0:" : ":");
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
          lines.push("", heading(label), value || "-");
        } else {
          lines.push(heading(label) + " " + (value || "-"));
        }
      });
      lines.push("", form.getAttribute("data-outro"));
      body = lines.join("\n").replace(/\n{3,}/g, "\n\n");
      var subject = form.getAttribute("data-subject");
      var key = form.getAttribute("data-subject-field");
      if (key && form.elements[key].value.trim()) subject += ": " + form.elements[key].value.trim();
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
