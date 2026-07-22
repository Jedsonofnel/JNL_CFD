;;; (nabla fvm bindings) ; re-exported C FVM bindings for internal documentation

(local opt (require :nabla.core.optional))
(local internal (opt.require :nabla.fvm_internal))

;;; Systems

(fn new-fvsys [mesh]
  "Create a new fvsys from a polymesh2D"
  (internal.fvsys_new mesh))

;;; Field operations

(fn face-interp! [mesh src-cw dst-fw]
  "Face interpolate cellwise src to facewise dst"
  (internal.face_interp mesh src-cw dst-fw))

(fn face-normal-cw! [mesh x-cw y-cw dst-fw]
  "Calculate face normals from cellwise x and y vectors onto facewise dst"
  (internal.face_normal_c mesh x-cw y-cw dst-fw))

;;; Implicit system assembly ops

(fn laplacian-k! [sys mesh gamma-k]
  "Apply laplacian operator to system with constant gamma"
  (internal.laplacian_k sys mesh gamma-k))

(fn div-uds-k! [sys mesh rho-k un]
  "Apply divergence op with UDS interpolation to sys with constant rho"
  (internal.div_uds_k sys mesh rho-k un))

(fn su-v-k! [sys mesh su-k]
  "Apply constant volumetric source term to sys"
  (internal.su_v_k sys mesh su-k))

;;; Patch closing (BC sys application)

(fn patch-s-close-d! [sys mesh patch-name value]
  "Close patch with patch-name on system matrix, dirichlet at value"
  (internal.patch_s_close_d sys mesh patch-name value))

(fn patch-s-close-n! [sys mesh patch-name grad-n]
  "Close patch with patch-name on system matrix, neumann at value"
  (internal.patch_s_close_n sys mesh patch-name grad-n))

(fn patch-s-close-r! [sys mesh patch-name a b c]
  "Close patch with patch-name on system matrix, robin with a b c"
  (internal.patch_s_close_r sys mesh patch-name a b c))

;;; Krylov solving

(fn new-solver-cg-jac [sys phi tol pool-cw]
  "Create a new Jacobi-preconditioned CG solver for phi, no mutation"
  (internal.new_solver_cg_jac sys phi tol pool-cw))

(fn new-solver-cg-dic [sys phi tol pool-cw]
  "Create a new DIC-preconditioned CG solver for phi, no mutation"
  (internal.new_solver_cg_dic sys phi tol pool-cw))

(fn new-solver-bicgstab-jac [sys phi tol pool-cw]
  "Create a new Jacobi-preconditioned BiCGSTAB solver for phi, no mutation"
  (internal.new_solver_bicgstab_jac sys phi tol pool-cw))

(fn new-solver-bicgstab-dilu [sys phi tol pool-cw]
  "Create a new DILU-preconditioned BiCGSTAB solver for phi, no mutation"
  (internal.new_solver_bicgstab_dilu sys phi tol pool-cw))

(fn new-solver-gmres-dilu [sys phi tol pool-cw restart]
  "Create a new DILU-preconditioned GMRES solver for phi with n restarts, no mutation"
  (internal.new_solver_gmres_dilu sys phi tol restart pool-cw))

;;; Public exports

{: new-fvsys
 ;; Field operators
 : face-interp!
 : face-normal-cw!
 ;; Implicit operators
 : laplacian-k!
 : div-uds-k!
 : su-v-k!
 ;; BC closing
 : patch-s-close-d!
 : patch-s-close-n!
 : patch-s-close-r!
 ;; Krylov solving
 : new-solver-cg-jac
 : new-solver-cg-dic
 : new-solver-bicgstab-jac
 : new-solver-bicgstab-dilu
 : new-solver-gmres-dilu
 ;; END
 }
