;;; (nabla mesh init) ; main re-export

(local cartmesh2d (require :nabla.mesh.cartmesh2d))

(fn resolve [{: meshkind : spec}]
  (case meshkind
    :cartmesh2d (cartmesh2d.resolve spec)
    _ (error (string.format "unrecognised mesh spec kind: '%s'" meshkind))))

{:cartmesh2d cartmesh2d.build : resolve}
