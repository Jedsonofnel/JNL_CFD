;;; (nabla mesh cartmesh2d) ; 2D Cartesian mesh generation

(local opt (require :nabla.core.optional))
(local internal (opt.require :nabla.strucmesh2d_internal))
(local {: assert-number} (require :nabla.core.validation))

(fn build [width height nx ny]
  "Build a cartesion mesh with nx * ny cells over a width * height rectangular domain"
  (assert-number width "cartmesh2d build width")
  (assert-number height "cartmesh2d build height")
  (assert-number nx "cartmesh2d build nx") ; TODO check positive integer
  (assert-number ny "cartmesh2d build ny") ; TODO check positive integer
  {:meshkind :cartmesh2d :spec {: width : height : nx : ny}})

(fn resolve [{: width : height : nx : ny}]
  (internal.cartmesh width height nx ny))

{: build
 : resolve
 ;; enum strings
 :NORTH :north
 :TOP :north
 :EAST :east
 :RIGHT :east
 :SOUTH :south
 :BOTTOM :south
 :WEST :west
 :LEFT :west}
