// clipboard.js
//
// Handles copy-to-clipboard for two button types:
//   .chip-copy      — copies the data-clipboard attribute (an inline R path)
//   .btn-copy-setup — copies the data-clipboard attribute (a setup code line)
//
// Uses document-level delegation so dynamically rendered Shiny UI buttons
// are handled without re-binding after each renderUI update.

// copyRmdText — reads the hidden #rmd-output element and copies its text content.
// Called by the "Copy inline code" button in Panel 3.
function copyRmdText() {
  var el = document.getElementById('rmd-output');
  if (!el) return;
  var text = el.textContent || el.innerText || '';

  navigator.clipboard.writeText(text).then(function() {
    var btn = document.getElementById('copy-rmd-btn');
    if (!btn) return;
    var original = btn.innerHTML;
    btn.innerHTML = '&#10003; Copied!';
    btn.classList.add('btn-copy-rmd-success');
    setTimeout(function() {
      btn.innerHTML = original;
      btn.classList.remove('btn-copy-rmd-success');
    }, 1500);
  }).catch(function() {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity  = '0';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
  });
}

// Toggle a type-filter badge. Sends the type string to Shiny; clicking the
// active badge again clears the filter (Shiny handles the toggle logic).
// Applies .type-filter-badge-active to the clicked button and removes it from
// all siblings so the UI reflects the current state immediately.
// Toggle a type-filter badge additively. Each badge can be on or off
// independently. Sends the full set of active types to Shiny as a
// comma-separated string (empty string = no filter = show all).
function draftToggleTypeFilter(btn) {
  btn.classList.toggle('type-filter-badge-active');

  var allBadges = btn.closest('.env-type-filter-row').querySelectorAll('.type-filter-badge');
  var active    = [];
  allBadges.forEach(function(b) {
    if (b.classList.contains('type-filter-badge-active')) {
      active.push(b.getAttribute('data-type'));
    }
  });

  Shiny.setInputValue('env_type_filter', active.join(','), {priority: 'event'});
}

// Toggle the settings box when the gear button is clicked.
// Handled here rather than server-side to avoid a shinyjs dependency.
document.addEventListener('click', function(e) {
  if (e.target.closest('#settings_toggle')) {
    var box = document.getElementById('settings-box');
    if (box) box.style.display = box.style.display === 'none' ? 'block' : 'none';
  }
});

document.addEventListener('click', function(e) {
  var btn = e.target.closest('[data-clipboard]');
  if (!btn) return;

  var text = btn.getAttribute('data-clipboard');
  if (!text) return;

  navigator.clipboard.writeText(text).then(function() {
    // Brief visual feedback for 1.2s. Full-size buttons get a text label;
    // small chip-copy icon buttons just get the checkmark glyph.
    var original = btn.innerHTML;
    var isChip   = btn.classList.contains('chip-copy');
    btn.innerHTML = isChip ? '&#10003;' : '&#10003; Copied!';
    var cls = isChip ? 'chip-copy-success' : 'btn-copy-setup-chunk-success';
    btn.classList.add(cls);
    setTimeout(function() {
      btn.innerHTML = original;
      btn.classList.remove(cls);
    }, 1200);
  }).catch(function() {
    // Fallback for browsers without clipboard API (non-HTTPS localhost)
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity  = '0';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
  });
});
