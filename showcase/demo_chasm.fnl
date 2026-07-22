;; (demo_chasm) ; simple demo of CHASM for FVM

(local fvm (require :nabla.fvm))
(local {: bc : chasm} fvm)
(local cart (require :nabla.mesh.cartmesh2d))
(local ui (require :nabla.ui))

(local mesh (cart.build 1 1 20 20))

(local asm (chasm.new :laplace))

(let [phi (asm:scalar-prog! :phi)]
  (asm:main (fn [block]
              (block:emit! :sys-reset-s phi)
              (block:emit! :laplacian-k phi)
              (block:emit! :bc-close-s phi)
              (block:emit! :krylov-s phi {:solver :bicgstab-dilu}))))

(local bcs {:phi {cart.EAST (bc.dirichlet-s 0)
                  cart.WEST (bc.dirichlet-s 1)
                  :__default (bc.neumann-s 0)}})

(asm:bind mesh bcs)

(fn run []
  (let [vm (asm:start)]
    (vm:run-all)
    (ui.display-mesh mesh)
    (ui.set-field! :phi (asm:get-array :phi))
    (ui.view-field :phi)))

(run)
