(defpackage shop-replan-tests
  ;; watch out -- this shadows fiveam:fail
  (:shadowing-import-from #:shop3 #:fail)
  (:import-from #:shop3-pddl-helpers #:validate-replan)
  (:import-from #:shop3-openstacks #:divergence
           #:os-sequencedstrips-p5_1i)
  (:use #:common-lisp #:iterate #:fiveam #:shop3))

(in-package :shop-replan-tests)

(defun executed-prefix (last-action plan)
  (let ((pos (position last-action plan :test 'equalp)))
    (subseq plan 0
            (if (some 'numberp plan)
                ;; there are costs -- keep them
                (+ 2 pos)
                (1+ pos)))))

(in-package :shop3-openstacks)
;;; work around bug in CCL reader -- at least for the version I have.
(defparameter shop-replan-tests::*sample-failed-action*
  '(!make-product p4))
(defparameter shop-replan-tests::*sample-divergence*
  '((:delete (made p4)) (:add (waiting o4)) (:delete (started o4))))
(in-package :shop-replan-tests)


(defun test-replan (&key (problem 'shop3-openstacks::os-sequencedstrips-p5_1i) (on-failure :error)
                      (failed-action *sample-failed-action*) (divergence *sample-divergence*)
                      (pddl-domain (asdf:system-relative-pathname "shop3" "examples/openstacks-adl/domain.pddl"))
                      (pddl-problem  (asdf:system-relative-pathname "shop3" "examples/openstacks-adl/p01.pddl"))
                      (package :shop3-openstacks))
  (let ((r (make-initial-plan :problem problem)))
    (declare (type shop::plan-return r))
    ;; the following ugliness could be a with-accessors
    (let ((plan (shop::plan r))
          (plan-tree (shop::tree r))
          (plan-tree-hash (shop::lookup-table r))
          (search-state (shop::search-state r)))
      (let* ((executed (executed-prefix failed-action plan))
             (domain (shop3::find-domain (shop3::domain-name problem))))
        (assert (every #'(lambda (x) (member x plan :test 'eql)) executed))
        ;; ugh, this could be a number....
        (assert (or (equalp (first (last executed)) failed-action)
                    (equalp (second (reverse executed)) failed-action)))
        (multiple-value-bind (repaired new-plan-tree)
            (unwind-protect
                 (shop3:repair-plan domain plan plan-tree executed divergence search-state :plan-tree-hash plan-tree-hash)
              (shop-untrace))

          ;;(list executed plan)
          (values
           (validate-replan repaired :shop-domain domain :package package
                                     :pddl-domain pddl-domain
                                     :pddl-problem pddl-problem
                                     :on-failure on-failure)

           repaired
           new-plan-tree
           executed
           domain
           divergence))))))

(declaim
 (ftype
  (function (&key (:problem (or symbol shop3::problem)) (:problem-file (or pathname string)))
            (values shop::plan-return &optional))
  make-initial-plan))
(defun make-initial-plan (&key (problem 'shop3-openstacks::os-sequencedstrips-p5_1i)
                            (problem-file (asdf:system-relative-pathname "shop3" "examples/openstacks-adl/p01-manual.lisp")))
  (load problem-file)
  (let ((r (find-plans-stack problem :unpack-returns nil
                                     :verbose 0 :plan-tree t :repairable t)))
    (or (first r) (error "Failed to generate a plan for openstacks problem."))))


;;; never used.  But useful....
#+ignore (defun temp-file-pathname ()
  (uiop:with-temporary-file (:pathname pddl-plan-name :keep t)
    pddl-plan-name))

(def-suite* test-plan-repair)
(test test-simple-openstacks-repair
  (flet ((put-in-package (sexp)
           (let ((pddl-utils:*pddl-package* (find-package 'shop3-openstacks)))
             (pddl-utils:pddlify-tree sexp))))
    (is-true (test-replan))
    (is-true (test-replan
              :failed-action (put-in-package '(!START-ORDER O3 N4 N3))
              :divergence (put-in-package
                           '((:delete (started o3))
                             (:delete (stacks-avail n3))
                             (:add (stacks-avail n4))
                             (:add (waiting o3))
                             (:add (waiting o4))
                             (:delete (started o4))))))
    (is-true (test-replan
              :failed-action (put-in-package '(!START-ORDER O3 N4 N3))
              :divergence (put-in-package
                           '((:delete (started o3))
                             (:delete (stacks-avail n3))
                             (:add (stacks-avail n4))
                             (:add (waiting o3))
                             (:add (waiting o4))
                             (:delete (started o4))
                             (:delete (shipped o5))
                             (:add (started o5))))))))

#+nil (test-replan) ;; 3 divergences
; cpu time (non-gc) 0.022090 sec user, 0.000336 sec system
; cpu time (gc)     0.000000 sec user, 0.000000 sec system
; cpu time (total)  0.022090 sec user, 0.000336 sec system
; real time  0.022475 sec (99.78%)
; space allocation:
;  79,073 cons cells, 1,066,128 other bytes, 0 static bytes
; Page Faults: major: 0 (gc: 0), minor: 266 (gc: 0)


#+nil (test-replan :failed-action 'shop3-openstacks::(!START-ORDER O3 N4 N3)
                                :divergence 'shop3-openstacks::((:delete (started o3)) (:delete (stacks-avail n3)) (:add (stacks-avail n4))(:add (waiting o3)) (:add (waiting o4)) (:delete (started o4)))) ; 6 divergences
; cpu time (non-gc) 0.017568 sec user, 0.000205 sec system
; cpu time (gc)     0.000000 sec user, 0.000000 sec system
; cpu time (total)  0.017568 sec user, 0.000205 sec system
; real time  0.017773 sec (100.0%)
; space allocation:
;  61,398 cons cells, 942,432 other bytes, 0 static bytes
; Page Faults: major: 0 (gc: 0), minor: 252 (gc: 0)

#+nil (test-replan :failed-action 'shop3-openstacks::(!START-ORDER O3 N4 N3)
                                :divergence 'shop3-openstacks::((:delete (started o3)) (:delete (stacks-avail n3)) (:add (stacks-avail n4))(:add (waiting o3)) (:add (waiting o4)) (:delete (started o4)) (:delete (shipped o5)) (:add (started o5)))) ; 8 divergences
; cpu time (non-gc) 0.018829 sec user, 0.000177 sec system
; cpu time (gc)     0.000000 sec user, 0.000000 sec system
; cpu time (total)  0.018829 sec user, 0.000177 sec system
; real time  0.019005 sec (100.0%)
; space allocation:
;  65,463 cons cells, 978,176 other bytes, 0 static bytes
; Page Faults: major: 0 (gc: 0), minor: 158 (gc: 0)
