document.addEventListener("DOMContentLoaded", () => {
  const btn = document.getElementById("back-to-top");

  if (!btn) {
    return;
  }

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("id", "progress-circle");
  svg.setAttribute("width", "44");
  svg.setAttribute("height", "44");

  const circle = document.createElementNS(
    "http://www.w3.org/2000/svg",
    "circle",
  );
  circle.setAttribute("cx", "22");
  circle.setAttribute("cy", "22");
  circle.setAttribute("r", "20");
  circle.setAttribute("stroke-width", "4");
  circle.setAttribute("fill", "none");

  svg.appendChild(circle);
  btn.appendChild(svg);

  window.addEventListener("scroll", () => {
    if (window.scrollY > 50) {
      const circumference = 2 * 3.14 * 20;
      const scrollTop = window.scrollY;
      const docHeight =
        document.documentElement.scrollHeight - window.innerHeight;
      const scrollFraction = scrollTop / docHeight;
      const drawLength = circumference * scrollFraction;

      circle.style.strokeDashoffset = circumference - drawLength;
    }
  });
});
