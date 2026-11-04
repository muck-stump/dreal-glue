// T-h value probe (report.md T-h): same interval-arithmetic call table run
// against each OS's build of THE SAME ibex commit (352eeeb), endpoints
// printed as hex floats so differences are bit-exact and greppable.
// Compiled -O2 -ffp-contract=off on both sides so the arithmetic-vs-
// transcendental split the registration scores is libm/fenv, not codegen.
#include <cstdio>
#include <ibex.h>
using namespace ibex;
static const char* g_lbl = "";
static void pr(const Interval& x) {
  printf("%-8s [%a, %a]\n", g_lbl, x.lb(), x.ub());
}
#define P(name, expr) do { g_lbl = name; Interval r_ = (expr); pr(r_); } while (0)
int main() {
  Interval a(0.1, 0.2), b(-3.0, 7.0), c(0.5, 4.0), u(1.0, 1.0000001);
  P("add",  a + b);            P("sub",  a - c);
  P("mul",  a * b);            P("div",  a / Interval(0.75, 2.5));
  P("sqr",  sqr(a));           P("point",Interval(0.1) * Interval(0.2));
  P("sqrt", Interval(2.0));    P("sqrtI", sqrt(c));
  P("ln2",  Interval(2.0));    P("logI", log(c));
  P("exp",  exp(a));           P("sin",  sin(b));
  P("cos",  cos(b));           P("atan", atan(b));
  P("pow",  pow(c, Interval(2.5)));
  P("tiny", a * a + a);        P("big",  b / Interval(3.0));
  printf("mid %a diam %a\n", a.mid(), a.diam());
  return 0;
}
