(defpackage :openstacks-problem-translator-asd
  (:use :common-lisp :asdf)
  )
(in-package :openstacks-problem-translator-asd)

(defsystem openstacks-problem-translator
    :depends-on (:iterate :shop2 :shop2/pddl-helpers :alexandria)
  :components ((:file "problem-converter"))
  )
