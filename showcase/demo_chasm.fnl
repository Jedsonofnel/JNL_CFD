;; (demo_chasm) ; simple demo of CHASM for FVM

(local fvm (require :nabla.fvm))
(local {: bc : chasm :instructions i} fvm)
(local cart (require :nabla.mesh.cartmesh2d))
(local meshlib (require :nabla.mesh))
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

(meshlib.resolve mesh-spec)

(fn run []
  (let [rt (chasm.compile asm mesh-spec bcs)] ; compile to vm which allocates/resolves
    (chasm.run-all! rt)
    (ui.display-mesh rt.domains.__default.mesh)
    (ui.set-field! :phi (chasm.get-array :phi))
    (ui.view-field :phi)))

(run)
