;; (nabla core mangle) ; name mangling source of truth

(local valid (require :nabla.core.validation))
(local {: oneof} valid)

(fn reserved? [name]
  "Returns name if reserved"
  (name:match "^__(.+)"))

(fn reserved [name]
  "Prefixes name to make it reserved/internal"
  (if (reserved? name)
      name
      (.. "__" name)))

(fn component [field i]
  "Mangles name field to mean i'th component of field"
  (oneof i [:x :y] "component i")
  (.. (reserved field) "_" i))

(component :U :x)
