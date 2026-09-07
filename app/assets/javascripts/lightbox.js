// Expands a gallery tile to fill the screen, with arrow navigation.
(function () {
  "use strict";

  var gallery = document.querySelector("[data-lightbox-gallery]");
  if (!gallery) return;

  var triggers = Array.prototype.slice.call(
    gallery.querySelectorAll("[data-lightbox-index]")
  );
  var templates = Array.prototype.slice.call(
    gallery.querySelectorAll("[data-lightbox-full]")
  );
  if (!triggers.length) return;

  var current = -1;
  var lastFocused = null;
  var overlay = build();
  document.body.appendChild(overlay.root);

  function build() {
    var root = document.createElement("div");
    root.className = "lightbox";
    root.setAttribute("role", "dialog");
    root.setAttribute("aria-modal", "true");
    root.setAttribute("aria-label", "Expanded media");
    root.hidden = true;

    var stage = document.createElement("div");
    stage.className = "lightbox__stage";

    var frame = document.createElement("div");
    frame.className = "lightbox__frame";

    var close = button("lightbox__close", "Close", "×");
    var previous = button("lightbox__nav lightbox__nav--previous", "Previous", "‹");
    var next = button("lightbox__nav lightbox__nav--next", "Next", "›");
    var counter = document.createElement("p");
    counter.className = "lightbox__counter";

    stage.appendChild(frame);
    root.appendChild(close);
    root.appendChild(previous);
    root.appendChild(stage);
    root.appendChild(next);
    root.appendChild(counter);

    close.addEventListener("click", hide);
    previous.addEventListener("click", function () { step(-1); });
    next.addEventListener("click", function () { step(1); });
    root.addEventListener("click", function (event) {
      // Backdrop only: clicks on the media itself must not close.
      if (event.target === root || event.target === stage) hide();
    });

    return { root: root, frame: frame, counter: counter, close: close };
  }

  function button(className, label, glyph) {
    var element = document.createElement("button");
    element.type = "button";
    element.className = className;
    element.setAttribute("aria-label", label);
    element.innerHTML = "<span aria-hidden=\"true\">" + glyph + "</span>";
    return element;
  }

  function show(index) {
    var template = templates[index];
    if (!template) return;

    stopMedia();
    overlay.frame.replaceChildren(template.content.cloneNode(true));
    overlay.counter.textContent = index + 1 + " / " + triggers.length;
    current = index;

    if (overlay.root.hidden) {
      lastFocused = document.activeElement;
      overlay.root.hidden = false;
      document.body.classList.add("has-lightbox");
      document.addEventListener("keydown", onKeydown);
    }
    overlay.close.focus();
  }

  function hide() {
    if (overlay.root.hidden) return;
    stopMedia();
    overlay.frame.replaceChildren();
    overlay.root.hidden = true;
    document.body.classList.remove("has-lightbox");
    document.removeEventListener("keydown", onKeydown);
    if (lastFocused && lastFocused.focus) lastFocused.focus();
    current = -1;
  }

  function stopMedia() {
    var playing = overlay.frame.querySelector("video");
    if (playing) playing.pause();
  }

  function step(delta) {
    if (current < 0) return;
    show((current + delta + triggers.length) % triggers.length);
  }

  function onKeydown(event) {
    if (event.key === "Escape") { hide(); return; }
    if (event.key === "ArrowLeft") { event.preventDefault(); step(-1); return; }
    if (event.key === "ArrowRight") { event.preventDefault(); step(1); return; }
    if (event.key === "Tab") {
      // Keep focus inside the dialog while it is open.
      var focusable = overlay.root.querySelectorAll("button, video[controls]");
      if (!focusable.length) return;
      var first = focusable[0];
      var last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
  }

  triggers.forEach(function (trigger) {
    trigger.addEventListener("click", function () {
      show(Number(trigger.getAttribute("data-lightbox-index")));
    });
  });
})();
