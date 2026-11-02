// Filters the error code tables by code or text.
document.addEventListener("DOMContentLoaded", function () {
  var input = document.querySelector(".code-filter");
  if (!input) return;
  var groups = document.querySelectorAll(".code-group");
  var empty = document.querySelector(".code-empty");
  input.hidden = false;

  input.addEventListener("input", function () {
    var query = input.value.trim().toLowerCase();
    var shown = 0;
    groups.forEach(function (group) {
      var visible = 0;
      group.querySelectorAll("tbody tr").forEach(function (row) {
        var match = !query || row.textContent.toLowerCase().indexOf(query) !== -1;
        row.hidden = !match;
        if (match) visible++;
      });
      group.hidden = visible === 0;
      shown += visible;
    });
    if (empty) empty.hidden = shown !== 0;
  });
});
