;; (demo_chasm) ; simple demo of CHASM for FVM

(local fvm (require :nabla.fvm))
(local {: bc : chasm :instructions i} fvm)
(local cart (require :nabla.mesh.cartmesh2d))
(local ui (require :nabla.ui))

;; Mesh
(local mesh-spec (cart.build 1 1 20 20))

;; Variables
(local phi (chasm.scalar :phi))

;; Program blocks
(local main-block (chasm.block :main
                               [(i.sys-reset-s phi)
                                (i.laplacian-k phi)
                                (i.bc-close-s phi)
                                (i.krylov-s phi {:solver :bicgstab-dilu})]
                               {:max-iters 1}))

;; Create the assembly program (name, vars, main block)
(local asm (chasm.program :laplace [phi] main-block))

;; BC spec
(local bcs {:phi {cart.EAST (bc.dirichlet 0)
                  cart.WEST (bc.dirichlet 1)
                  bc.DEFAULT (bc.neumann 0)}})

(comment (let [meshlib (requier :nabla.mesh)
               mesh (meshlib.resolve mesh-spec)
               {: errors : warnings : bcs} (bc.resolve bcs asm.vars
                                                       (mesh:patches))]
           errors))

(fn run []
  (let [rt (chasm.compile asm mesh-spec bcs)] ; compile to vm which allocates/resolves
    (chasm.run-all! rt)
    (ui.display-mesh rt.domains.__default.mesh)
    (let [phi-array (chasm.get-array rt :phi)]
      (print (phi-array:max)))
    (ui.set-field! :phi (chasm.get-array rt :phi))
    (ui.view-field :phi)))

(comment (let [rt (chasm.compile asm mesh-spec bcs)
               phi-array (chasm.get-array rt :phi)]
           (chasm.get-sys+mesh+bcs rt :phi)
           (chasm.get-sys+mesh rt :phi)
           (length phi-array)))

(run)
