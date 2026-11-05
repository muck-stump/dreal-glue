;; isolation/wrong_unsat.smt2 — provenance fixture, READ-ME-FIRST
;;
;; The smallest dreal-level input found that fails on cell C (macOS):
;; the 4-line seed of the 22-test cluster.  Built by shrinking
;; github_issue_192 — every constraint but one dropped, that one
;; simplified to its trigger.  This fixture is NOT part of any cell's
;; suite; what the Linux cells prove is its ancestor github_issue_192
;; passing there (runs/failed.{A,B,D,E}.txt), while the dependency-level
;; linux answer comes from isolation/run.sh --container (4/4):
;;
;;   expected: delta-sat with delta = 0.001      r0 = 0 is a witness
;;   cell C : unsat                              (macOS, empty ICP box)
;;
;; Why this and not something simpler — measured dreal answers on THIS
;; MAC (cell C) for `(< (- S C r0) 0.0)` (wrong answer = `unsat`):
;;   S=0.1, C in {1, 2, 10, 1e8, 1e9, 567495437.0} -> unsat
;;   S in {1.0, 2.0, 0.5, 0.25}, C in {1, 2, 10}  -> delta-sat (fold exact)
;;   S in {1.0, 0.5}, C=567495437.0               -> delta-sat
;;   S=8.787792382, C=567495437.0 -> unsat ; C=1   -> delta-sat
;;   S=0.1 with `(+ 0.1 C r0)` -> unsat ; r0 removed entirely -> delta-sat
;;   S=0.1000000000000001, C=10: `-` -> delta-sat, `+` -> unsat (no iff)
;; dreal stores a decimal no double represents as a tight double
;; interval ("capsule", IbexConverter::VisitRealConstant) — those are the
;; literals that collapse on darwin — but the boundary is not a clean
;; iff; the mechanism only ever proves itself through the dependency
;; (ibex_rounding_isolation_test.cc checks [3] and [4]).
;;
;; This file exists so `run.sh --dreal <binary>` can show the dreal-level
;; symptom; the checks themselves use no dreal code at all.
(set-logic QF_NRA)
(declare-const r0 Real)
(assert (< (- 0.1 10 r0) 0.0))
(check-sat)
