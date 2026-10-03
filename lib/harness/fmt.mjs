// /lib/fmt.mjs: formatting helpers for item generators. Italian conventions:
// decimal comma, thousands with a dot, no locale functions (they are not
// available to generators and would depend on the browser).

const MINUS = "−";

// A number with the decimal comma: it(3.5) is "3,5"; it(2, 2) is "2,00".
export function it(n, decimals) {
  const text = decimals === undefined ? String(n) : n.toFixed(decimals);
  return text.replace(".", ",");
}

// A number with a sign: signed(3) is "+3", signed(-3) is "−3".
export function signed(n) {
  return n < 0 ? MINUS + String(-n).replace(".", ",") : "+" + String(n).replace(".", ",");
}

// Thousands with a dot: thousands(1234567) is "1.234.567".
export function thousands(n) {
  const [whole, fraction] = String(Math.abs(n)).split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return (n < 0 ? "-" : "") + grouped + (fraction ? "," + fraction : "");
}

// An amount with two decimals: euro(1234.5) is "1.234,50".
export function euro(n) {
  const [whole, cents] = Math.abs(n).toFixed(2).split(".");
  return (n < 0 ? "-" : "") + thousands(Number(whole)) + "," + cents;
}

// A fraction in LaTeX: frac(3, 4) is "\frac{3}{4}".
export function frac(n, d) {
  return "\\frac{" + n + "}{" + d + "}";
}

// Mathematics for the app's renderer: math("x+1") is "$x+1$".
export function math(latex) {
  return "$" + latex + "$";
}

// "a, b e c".
export function list(items) {
  if (items.length < 2) return items.join("");
  return items.slice(0, -1).join(", ") + " e " + items[items.length - 1];
}
