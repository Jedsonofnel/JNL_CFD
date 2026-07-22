;;; (nabla core pool) ; scratch pool bindings

(local opt (require :nabla.core.optional))
(local internal (opt.require :nabla.scratch_internal))
(local {: positive-integer?} (require :nabla.util))

(fn new [array-length]
  "Create a new scratch pool of fixed-length f64 arrays, grows automatically"
  (when (not (positive-integer? array-length))
    (error "new pool array-length must be a positive integer" 2))
  (internal.new array-length))

{: new}
