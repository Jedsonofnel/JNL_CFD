;;; (nabla core array) ; array bindings

(local opt (require :nabla.core.optional))
(local internal (opt.require :nabla.array_internal))

(fn new [len init]
  "Allocate a new array of length len set to init or zeroed"
  (internal.new len (or init 0)))

(fn view [src offset len]
  "View a sub-range of an existing array starting at offset with length len"
  (internal.view src offset len))

{: new : view}
