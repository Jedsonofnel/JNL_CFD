;;; (nabal core) ;  main entrypoint

(local validation (require :nabla.core.validation))
(local optional (require :nabla.core.optional))

{: validation
 :valid validation
 :mangle (require :nabla.core.mangle)
 :util (require :nabla.core.util)
 : optional
 :opt optional
 :pool (require :nabla.core.pool)
 :array (require :nabla.core.array)}
