;;; (nabla core optional) optional requiring of C bindings (so tests run without them)

(fn optional-require [modname]
  "Require a module, returning a deferred-error stub if unavailable"
  (let [[ok mod] [(pcall require modname)]]
    (if ok
        mod
        (setmetatable {} {:__index (fn [_ k]
                                     #(error (.. modname
                                                 " not available - called '" k
                                                 "'")
                                             2))}))))

{:require optional-require}
