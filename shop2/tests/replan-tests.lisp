(defpackage shop-replan-tests
  ;; watch out -- this shadows fiveam:fail
  (:shadowing-import-from #:shop2 #:fail)
  (:import-from #:shop2-openstacks #:divergence
           #:os-sequencedstrips-p5_1i)
  (:use #:common-lisp #:iterate #:fiveam #:shop2))

(in-package :shop-replan-tests)

(defun executed-prefix (last-action plan)
  (let ((pos (position last-action plan :test 'equalp)))
    (subseq plan 0
            (if (some 'numberp plan)
                ;; there are costs -- keep them
                (+ 2 pos)
                (1+ pos)))))

(defun test-replan ()
  (load (asdf:system-relative-pathname "shop2" "examples/openstacks-adl/p01-manual.lisp"))
  (let ((r (multiple-value-list (find-plans-stack
                                 'shop2-openstacks::os-sequencedstrips-p5_1i :verbose 0 :plan-tree t :repairable t))))
    (unless (first r) (error "Failed to generate a plan for openstacks problem."))
    (destructuring-bind ((plan) (plan-tree) (plan-tree-hash) search-state)
        r
      (let* ((executed (executed-prefix 'shop2-openstacks::(!make-product p4) plan))
             (domain (find-domain (shop2::domain-name (find-problem 'os-sequencedstrips-p5_1i))))
             (divergence 'shop2-openstacks::((:delete (made p4)) (:add (waiting o4)) (:delete (started o4)))))
        ;;(list executed plan)
        (shop2:repair-plan domain plan plan-tree executed divergence search-state :plan-tree-hash plan-tree-hash)))))

(defun find-divergence (shop-plan)
  (find-if #'(lambda (x) (when (listp x) ; ignore costs, if present
                           (eq (first x) :divergence)))
           shop-plan))

(defun temp-file-pathname ()
  (uiop:with-temporary-file (:pathname pddl-plan-name :keep t)
    pddl-plan-name))

(defun coerce-pddl-argument (pddl-argument)
  (etypecase pddl-argument
    (cons pddl-argument)
    ((or string pathname) (pddl-utils:read-pddl-file pddl-argument))))

(defun validate-replan (repaired-plan &key (shop-domain *domain*) (package *package*) pddl-domain pddl-problem)
  (let* ((pddl-domain (coerce-pddl-argument pddl-domain))
         (pddl-problem (coerce-pddl-argument pddl-problem))
         (pddl-plan-sexp (pddl-plan-for-replan repaired-plan :shop-domain shop-domain :package package))
         (divergence (find-divergence repaired-plan))
         (pddl-domain (pddl-domain-for-replan divergence pddl-problem pddl-domain))
         (pddl-problem-filename (etypecase pddl-problem
                                  (string pddl-problem)
                                  (pathname (namestring pddl-problem))
                                  (pddl-utils:problem
                                   (or (uiop:with-temporary-file (:pathname pname :stream str :keep t)
                                         (pddl-utils:pprint-pddl pddl-problem str)
                                         (namestring pname))
                                       (error "Error writing problem to file")))))
         (pddl-plan-filename
           (namestring (uiop:with-temporary-file (:pathname temp-file-pathname :stream str :keep t)
                         (pddl-utils:print-pddl-plan pddl-plan-sexp str)
                         temp-file-pathname)))
         (pddl-domain-filename
           (namestring (uiop:with-temporary-file (:pathname pddl-domain-name :stream str :keep t)
                         (pddl-utils:pprint-pddl pddl-domain str)
                         pddl-domain-name))))
    (let ((validation-command (format nil "validate -vv -x ~a ~a ~a"
                                      pddl-domain-filename pddl-problem-filename pddl-plan-filename)))
      (multiple-value-bind (output error-output exit-code)
          (uiop:run-program validation-command
                            :ignore-error-status t
                            :output '(:string :stripped t)
                            :error-output '(:string :stripped t))
        (if (zerop exit-code)
            t
            (progn 
              (format t "Validation failed with error code ~d~%Command: ~a~%Error output:~%~T~A~%Output:~%~T~A~%"
                      exit-code validation-command error-output output)
              nil))))))

(defun pddl-plan-for-replan (repaired-plan &key (shop-domain *domain*) (package *package*))
  (let ((pos (position :divergence repaired-plan :key #'(lambda (x) (and (listp x) (first x))))))
    (unless pos (error "No :DIVERGENCE in the replan."))
    (let ((new-plan (copy-list repaired-plan)))
      (setf (nth pos new-plan)
            (list (intern :divergence package)))
      (pddl-utils:pddlify-tree (shop2::pddl-plan shop-domain  new-plan)))))

(defun pddl-domain-for-replan (divergence pddl-problem pddl-domain)
  "DIVERGENCE is a divergence expression -- (:DIVERGENCE ([:ADD|:DELETE] <fact>)*)"
  (flet ((find-all-keys (x)
           (mapcar 'second (remove-if-not #'(lambda (l) (eq (first l) x)) (rest divergence)))))
    (let* ((pddl-domain (pddl-utils:canonicalize-domain pddl-domain))
           (constant-defs (pddl-utils:typelist-to-alist (pddl-utils:canonicalize-types (pddl-utils:domain-constants pddl-domain))))
           (object-defs (pddl-utils:typelist-to-alist (pddl-utils:canonicalize-types (pddl-utils:problem-objects pddl-problem))))
           (add-list (find-all-keys :add))
           (delete-list (find-all-keys :delete))
           (constants (remove-duplicates
                       (append
                        (alexandria:mappend #'rest add-list)
                        (alexandria:mappend #'rest delete-list))))
           (new-constants (iter (for constant in constants)
                            (with predefined = (mapcar #'car constant-defs))
                            ;; note STRING-EQUAL because of possible package mismatches
                            (unless (member constant predefined :test 'string-equal)
                              (appending `(,constant - ,(or (alexandria:assoc-value object-defs constant :test 'string-equal)
                                                             (error "No type for constant ~a" constant)))))))
           (new-action (pddl-utils:make-action 'divergence nil
                                               :precondition nil
                                               :effect `(and ,@add-list
                                                             ,@(mapcar #'(lambda (fact)
                                                                           `(not ,fact))
                                                                       delete-list))))
           (new-domain (pddl-utils:insert-domain-actions pddl-domain (list new-action))))
      (pddl-utils:add-to-domain-constants new-domain new-constants)
      new-domain)))

