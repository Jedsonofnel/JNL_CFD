;; (nabla core mangle) ; name mangling source of truth

(local valid (require :nabla.core.validation))

(fn component [name]
  (valid.identifier name "component name"))
