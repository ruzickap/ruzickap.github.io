const toast = document.getElementById("notification");
toast.addEventListener("shown.bs.toast", () => {
  const button = toast.querySelector(".toast-body>button");
  button?.click();
});
