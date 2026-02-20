(function () {
  function setupFocusResultToggle() {
    var trigger = document.getElementById("print-view-btn");
    if (!trigger) return;

    trigger.addEventListener("click", function () {
      document.body.classList.toggle("focus-result");
    });
  }

  function setupClearButton() {
    var clearBtn = document.getElementById("clear-btn");
    if (!clearBtn) return;

    clearBtn.addEventListener("click", function () {
      var seqA = document.getElementById("sequenceA");
      var seqB = document.getElementById("sequenceB");
      var pdfA = document.getElementById("pdfA");
      var pdfB = document.getElementById("pdfB");
      if (seqA) seqA.value = "";
      if (seqB) seqB.value = "";
      if (pdfA) pdfA.value = "";
      if (pdfB) pdfB.value = "";
    });
  }

  function attach() {
    setupFocusResultToggle();
    setupClearButton();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", attach);
  } else {
    attach();
  }
})();
