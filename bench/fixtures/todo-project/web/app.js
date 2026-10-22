// Description: front-end bootstrap
import { renderCart } from "./cart-view.js";

function fetchTodos() {
  return [];
}

// TODO: lazy-load the catalog page
export function boot() {
  console.log("boot"); // TODO: remove debug logging before launch
  renderCart(document.getElementById("cart"));
  return fetchTodos();
}
