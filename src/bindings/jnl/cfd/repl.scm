(define-module (jnl cfd repl))

(use-modules (system repl repl)
             (system repl common)
             (jnl cfd geo2d)
             (ice-9 readline))

(setenv "GUILE_HISTORY" "/dev/null")
(activate-readline)

(variable-set! (module-variable (resolve-module '(system repl common)) '*version*)
               "JNL CFD 0.0.1")

(repl-default-prompt-set!
  (lambda (repl)
    (let ((level (length (fluid-ref (@@ (system repl repl) *repl-stack*))))) 
      (if (<= level 1)
          "jnlcfd> "
          (format #f "jnlcfd [~a]> " (1- level))))))

(run-repl (make-repl 'scheme))
