const header_html = `
<a href="/index.html">Simulation</a>
<a href="/upload.html">Upload</a>
<a href="/chamber_test.html">Chamber testing</a>
`;

function init() {
  const header = document.createElement("div");
  header.innerHTML = header_html;
  document.body.insertBefore(header, document.body.firstChild);
}

init();
