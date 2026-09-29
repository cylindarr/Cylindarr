// Dark by default, light on request; the choice is kept per browser. The head sets it before the page paints.
(function () {
  const root = document.documentElement;
  const button = document.querySelector("[data-theme-toggle]");
  function label() {
    const dark = root.dataset.theme !== "light";
    button.textContent = dark ? "Light" : "Dark";
    button.setAttribute("aria-label", dark ? "Switch to the light theme" : "Switch to the dark theme");
  }
  if (button) {
    label();
    button.addEventListener("click", function () {
      root.dataset.theme = root.dataset.theme === "light" ? "dark" : "light";
      localStorage.setItem("cylindarr-theme", root.dataset.theme);
      label();
    });
  }
  // Mark the section being shown in the navigation.
  const path = location.pathname;
  for (const a of document.querySelectorAll("header nav a")) {
    const href = a.getAttribute("href");
    if (href === "/" ? path === "/" : path.startsWith(href)) a.setAttribute("aria-current", "page");
  }
})();
