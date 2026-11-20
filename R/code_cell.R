#' Code cell UI
#'
#' A code box above the results feed. Ctrl/Cmd+Enter or the Run button sends
#' the code to the server as `input$code_run`; the box then clears, like a
#' console. Up and Down arrows step through earlier commands when the cursor
#' is on the first or last line, so multi-line editing still works. History
#' lives in the browser only, for this page load. Tab inserts two spaces.
#' @noRd
code_cell_ui <- function() {
  shiny::div(
    class = "mb-3",
    shiny::tags$textarea(
      id = "code_input", rows = 3, spellcheck = "false",
      `data-shiny-no-bind-input` = "",
      class = "form-control font-monospace small",
      placeholder = paste(
        "R code, for example head(de_results) or plot(...).",
        "Ctrl/Cmd+Enter runs it; Up/Down recall earlier commands."
      )
    ),
    shiny::div(
      class = "d-flex align-items-center gap-2 mt-1",
      shiny::tags$button(id = "code_run_btn", type = "button",
                         class = "btn btn-outline-primary btn-sm", "Run code"),
      shiny::span(class = "small text-muted",
                  "Project objects are read-only here; your own variables are kept between runs.")
    ),
    shiny::uiOutput("code_error"),
    shiny::tags$script(shiny::HTML(code_cell_js))
  )
}

code_cell_js <- "
(function() {
  const history = [];
  let pos = 0, draft = '';
  function box() { return document.getElementById('code_input'); }
  function setCode(ta, text) {
    ta.value = text;
    ta.selectionStart = ta.selectionEnd = text.length;
  }
  function run() {
    const ta = box();
    const code = ta.value;
    if (!code.trim()) return;
    if (history[history.length - 1] !== code) history.push(code);
    pos = history.length; draft = '';
    ta.value = '';
    Shiny.setInputValue('code_run', {code: code, nonce: Date.now()}, {priority: 'event'});
  }
  document.addEventListener('click', function(e) {
    if (e.target && e.target.id === 'code_run_btn') run();
  });
  document.addEventListener('keydown', function(e) {
    const ta = e.target;
    if (!ta || ta.id !== 'code_input') return;
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault(); run(); return;
    }
    if (e.key === 'Tab' && !e.shiftKey) {
      e.preventDefault();
      const s = ta.selectionStart;
      ta.value = ta.value.slice(0, s) + '  ' + ta.value.slice(ta.selectionEnd);
      ta.selectionStart = ta.selectionEnd = s + 2;
      return;
    }
    const onFirstLine = !ta.value.slice(0, ta.selectionStart).includes('\\n');
    const onLastLine = !ta.value.slice(ta.selectionEnd).includes('\\n');
    if (e.key === 'ArrowUp' && onFirstLine && pos > 0) {
      e.preventDefault();
      if (pos === history.length) draft = ta.value;
      pos -= 1; setCode(ta, history[pos]);
    } else if (e.key === 'ArrowDown' && onLastLine && pos < history.length) {
      e.preventDefault();
      pos += 1; setCode(ta, pos === history.length ? draft : history[pos]);
    }
  });
})();
"
