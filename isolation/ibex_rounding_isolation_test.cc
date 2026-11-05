// isolation/ibex_rounding_isolation_test.cc
//
// ISOLATION TEST for the cell-C "22-test wrong-unsat cluster".
// ===================================================================
// This file contains NO dreal code on purpose.  It exercises exactly two
// things: <fenv.h> (the OS) and ibex (the dependency that cluster is
// attributed to).  Adding/reading a test never changes solver logic, and
// this repo's cells pin a pristine dreal4 checkout, so the test lives here
// (glue repo) and never touches the 445-target suite inside dreal4/.
//
// Why this isolates the cluster (evidence: report.md round 7 / K row,
// runs/K-mechanism.txt, runs/T-h-fenv.txt):
//
//   ibex's bundled filib interval library picks its rounding strategy in
//   the HEADER rounding_control/rounding_control_double.hpp:
//       #elif defined(__STDC_IEC_559__)  -> rounding_control_double_iso9x.icc
//                                          (fesetround dance = rigorous)
//       #else                           -> rounding_control_double_void.icc
//                                          (downward() {} = NOP!)
//   The force-define of __STDC_IEC_559__ in rounding_control_config.hpp is
//   commented out (byte-identical on both OSes).  glibc's header chain
//   makes the macro visible; no darwin toolchain chain ever does
//   (measured: darwin 0/0, linux 1/1 — runs/K-mechanism.txt).  OS-level
//   fesetround works on BOTH OSes (runs/T-h-fenv.txt), so darwin's ibex
//   simply never switches rounding mode => round-to-nearest interval
//   endpoints => non-rigorous enclosure => ibex's forward/backward
//   propagation can empty a strictly satisfiable constraint => dreal must
//   answer `unsat` where a witness exists (the cluster's C1 failure mode).
//
// Smallest live dreal-level input (provenance only; NOT run by this test
// — see wrong_unsat.smt2 / run.sh --dreal):
//     (declare-const r0 Real)
//     (assert (< (- 0.1 10 r0) 0.0))       ; delta-sat (r0 = 0), answered `unsat` on cell C
//   Shrink trail (every dreal answer below measured ON THIS MAC; scan
//   table in wrong_unsat.smt2): start from github_issue_192 — pure
//   linear, no libm, no quantifiers, which is why the investigation could
//   rule libm out at the root — drop the worklist-fixpoint option and the
//   unused assert, then sweep the constants: `(< (- S C r0) 0.0)` says
//   `unsat` for S=0.1 with C in {1, 2, 10, 1e8, 1e9, 567495437.0} but
//   `delta-sat` for S in {1.0, 2.0, 0.5, 0.25} with C <= 10 (and for
//   S in {1.0, 0.5} with C=567495437.0): their fold is exact; drop r0
//   and it says `delta-sat`.  dreal stores a decimal no double represents as
//   a tight double interval ("capsule", IbexConverter::VisitRealConstant)
//   rather than a point — that capsule is what round-to-nearest collapses
//   on darwin.  The boundary is not syntactic (0.1000000000000001 passes
//   with a trailing `-`, fails with a `+`), so this test asserts the
//   mechanism inside ibex, not an input grammar; the linux side is
//   answered check-by-check by the container run plus every Linux cell
//   passing all 240 smt2/dr oracle tests unchanged.
//
// Checks (each one is an assertion; expectation shown in run.sh output):
//   [1] os-fesetround          control: does fegetround(FE_DOWNWARD/UP)
//                              actually change the result of a + b,
//                              WITH ibex's own copts in force?   -> PASS/PASS
//   [2] ibex-rounding-selector: does ibex's compiled rounding_control
//                              template (filib::rounding_control<double,
//                              bool>) engage directed rounding?  -> FAIL/PASS
//   [3] ibex-interval-enclosure: does ibex::Interval addition bracket
//                              the exact real result?            -> FAIL/PASS
//   [4] ibex-wrong-unsat:      does ibex's own Function::backward empty a
//                              satisfiable box (=> solver says unsat)? FAIL/PASS
//   darwin(red,red,red) vs linux(green,green,green) = the cluster in one file.
//
// Compile: see isolation/run.sh (needs only pkg-config ibex).

#include <fenv.h>
#include <cmath>
#include <cstdio>
#include <sstream>
#include <string>

#include <ibex.h>

namespace {

template <class T>
std::string Show(const T& v) {
  std::ostringstream os;
  os << v;
  return os.str();
}

std::string Hex(const double v) {
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%#.17g", v);
  return buf;
}

int g_passed = 0;
int g_failed = 0;

void Report(const char* name, const bool ok, const std::string& detail) {
  ++(ok ? g_passed : g_failed);
  std::printf("[%s] %s\n       %s\n", ok ? "PASS" : "FAIL", name,
              detail.c_str());
}

// Exact outward brackets of "a + b" (a, b doubles) computed with the OS's
// own directed rounding.  These are the *reference* values: a rigorous
// interval implementation must satisfy  ib.lb() <= down  and  ib.ub() >= up.
// Volatile + restore-to-nearest keeps the two additions unfolder.
double DownRound(const double a, const double b) {
  const volatile double va = a;
  const volatile double vb = b;
  volatile double r = 0.0;
  fesetround(FE_DOWNWARD);
  r = va + vb;
  fesetround(FE_TONEAREST);
  return r;
}

double UpRound(const double a, const double b) {
  const volatile double va = a;
  const volatile double vb = b;
  volatile double r = 0.0;
  fesetround(FE_UPWARD);
  r = va + vb;
  fesetround(FE_TONEAREST);
  return r;
}

// [1] The OS rounding switch itself — the control.  Runs with ibex's own
// -frounding-math in force (run.sh passes pkg-config cflags).  This must
// PASS on every system: runs/T-h-fenv.txt already measured it green on
// darwin and linux, so a red here would mean the harness, not ibex.
void CheckOsFesetround() {
  fesetround(FE_TONEAREST);
  const int rc_down = fesetround(FE_DOWNWARD);
  const int mode_after = fegetround();
  fesetround(FE_TONEAREST);

  const double lo = DownRound(0.1, -3.0);
  const double hi = UpRound(0.1, -3.0);
  const bool modes_appear =
      (rc_down == 0) && (mode_after != FE_TONEAREST) && (lo < hi);
  std::ostringstream d;
  d << "fesetround(FE_DOWNWARD) rc=" << rc_down
    << " fegetround=" << mode_after << "; 0.1+(-3): down=" << Hex(lo)
    << " up=" << Hex(hi);
  if (!modes_appear) d << "  [rounding switch inert on this machine]";
  Report("os-fesetround", modes_appear, d.str());
  fesetround(FE_TONEAREST);
}

// [2] ibex's own rounding selector.  This is the compile-time branch the
// K row of report.md identifies as the root cause: on darwin the macro
// never gets defined, so ibex's headers instantiate the void strategy and
// every downward()/upward() is an empty body.  The check is done on both
// template specializations because different fp_traits classes inherit
// different ones.
void CheckIbexRoundingSelector() {
#ifdef __STDC_IEC_559__
  const char* macro = "__STDC_IEC_559__ defined (selects iso9x strategy)";
#else
  const char* macro =
      "__STDC_IEC_559__ NOT defined (selects void strategy: NOP bodies)";
#endif
  fesetround(FE_TONEAREST);
  bool ok = true;
  std::ostringstream d;
  d << macro << "\n       ";

  filib::rounding_control<double, false>::downward();
  const bool d0 = (fegetround() == FE_DOWNWARD);
  d << "rc0<false>.downward() -> fegetround=" << fegetround() << " ";
  ok = ok && d0;
  filib::rounding_control<double, false>::upward();
  const bool u0 = (fegetround() == FE_UPWARD);
  d << "upward() -> " << fegetround() << " ";
  ok = ok && u0;
  filib::rounding_control<double, true>::downward();
  const bool d1 = (fegetround() == FE_DOWNWARD);
  d << "rc0<true>.downward() -> " << fegetround() << "\n       ";
  ok = ok && d1;

  // Restore whatever tonearest means here, hard-set it too, whatever happened.
  filib::rounding_control<double, false>::tonearest();
  fesetround(FE_TONEAREST);
  Report("ibex-rounding-selector", ok, d.str());
}

// The literal dreal uses for the decimal 0.1: the tightest interval of
// doubles containing the real 0.1 (this is what makes the darwin collapse
// observable at all — a point literal that happens to be exact survives).
ibex::Interval DecimalLiteral() {
  return ibex::Interval(std::nextafter(0.1, 0.0),
                        std::nextafter(0.1, 1.0));
}

// [3] Rigorous enclosure: ibex::Interval addition has to bracket the exact
// real sums.  Reference bounds come from check [1] (OS primitives).
void CheckIntervalEnclosure() {
  const ibex::Interval lit = DecimalLiteral();
  const ibex::Interval c = ibex::Interval(-10.0) + lit;
  const double lo = DownRound(-10.0, lit.lb());
  const double hi = UpRound(-10.0, lit.ub());
  const bool ok = (c.lb() <= lo) && (c.ub() >= hi);
  std::ostringstream d;
  d << "Interval(-10.0) + [" << Hex(lit.lb()) << ", " << Hex(lit.ub())
    << "]\n       ibex = [" << Hex(c.lb()) << ", " << Hex(c.ub())
    << "]\n       exact = [" << Hex(lo) << ", " << Hex(hi)
    << "] (required hull)\n       width(ibex)=" << c.diam()
    << (c.lb() > lo ? "   <-- lost the lower end"
                    : (c.ub() < hi ? "   <-- lost the upper end" : ""));
  Report("ibex-interval-enclosure", ok, d.str());
  fesetround(FE_TONEAREST);
}

// [4] The behavioral failure itself, inside the dependency only: run
// ibex's backward propagation on the exact expression graph dreal's
// IbexConverter emits for `(< (- 0.1 10 r0) 0.0)` — two separate constant
// nodes (-10, capsule) plus the variable, strict `< 0` — starting from
// r0 = ENTIRE.  The constraint is satisfiable (witness below), so a
// non-empty box is the only legal answer: an empty box forces every
// solver on top of this contractor to answer `unsat` — that IS the
// cluster's failure mode.
void CheckWrongUnsat() {
  using ibex::Array;
  using ibex::ExprConstant;
  using ibex::ExprCtr;
  using ibex::ExprSymbol;
  using ibex::Interval;
  using ibex::IntervalVector;
  using ibex::NumConstraint;

  const Interval lit = DecimalLiteral();

  // Witness: at r0 = 0 the expression evaluates to the constant
  // interval (-10 + lit), upper end strictly negative, so the strict
  // `< 0` holds at r0 = 0 — the box may shrink, never empty.
  const Interval at_witness = Interval(-10.0) + lit;
  const bool witness_ok = at_witness.ub() < 0.0;

  const ExprSymbol& r0 = ExprSymbol::new_("r0");
  const ExprConstant& c10 = ExprConstant::new_scalar(-10.0);
  const ExprConstant& clit = ExprConstant::new_scalar(lit);
  const ExprConstant& zero = ExprConstant::new_scalar(0.0);
  const ExprCtr ctr = (c10 + clit) - r0 < zero;  // NOLINT(runtime/expr)
  const Array<const ExprSymbol> vars(r0);
  const NumConstraint nc(vars, ctr);

  IntervalVector box(1);
  box[0] = Interval::ALL_REALS;
  nc.f.backward(nc.right_hand_side(), box);

  const bool ok = witness_ok && !box[0].is_empty();
  std::ostringstream d;
  d << "constraint: " << Show(nc) << "\n       witness r0=0 gives "
    << Show(at_witness) << " (holds: " << (witness_ok ? "yes" : "NO")
    << ")\n       box after ibex Function::backward: r0 = " << Show(box[0]);
  if (box[0].is_empty()) {
    d << "\n       empty box = a solver built on this contractor must answer "
         "`unsat` (the cluster)";
  } else {
    d << "\n       box kept = a solver built on this contractor CAN answer "
         "delta-sat";
  }
  Report("ibex-wrong-unsat", ok, d.str());
  fesetround(FE_TONEAREST);
}

}  // namespace

int main() {
  std::printf("ibex isolation test (no dreal code) on %s | %s\n",
#ifdef __APPLE__
              "darwin",
#else
              "non-darwin",
#endif
#ifdef __clang__
              "clang");
#else
              "gcc");
#endif
  std::printf(
      "expected: darwin -> [1] PASS, [2][3][4] FAIL (the 22-test cluster);\n"
      "          linux  -> all PASS.  Details: isolation/README.md\n\n");

  CheckOsFesetround();
  CheckIbexRoundingSelector();
  CheckIntervalEnclosure();
  CheckWrongUnsat();

  std::printf("\n%d passed, %d failed%s\n", g_passed, g_failed,
              g_failed ? "   <-- dependency misbehaves on this system"
                       : "   <-- dependency behaves: no bug to isolate here");
  return g_failed ? 1 : 0;
}
