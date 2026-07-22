-- [nfnl] lua/nabla/fvm/bindings.fnl
local opt = require("nabla.core.optional")
local internal = opt.require("nabla.fvm_internal")
local function new_fvsys(mesh)
  return internal.fvsys_new(mesh)
end
local function face_interp_21(mesh, src_cw, dst_fw)
  return internal.face_interp(mesh, src_cw, dst_fw)
end
local function face_normal_cw_21(mesh, x_cw, y_cw, dst_fw)
  return internal.face_normal_c(mesh, x_cw, y_cw, dst_fw)
end
local function laplacian_k_21(sys, mesh, gamma_k)
  return internal.laplacian_k(sys, mesh, gamma_k)
end
local function div_uds_k_21(sys, mesh, rho_k, un)
  return internal.div_uds_k(sys, mesh, rho_k, un)
end
local function su_v_k_21(sys, mesh, su_k)
  return internal.su_v_k(sys, mesh, su_k)
end
local function patch_s_close_d_21(sys, mesh, patch_name, value)
  return internal.patch_s_close_d(sys, mesh, patch_name, value)
end
local function patch_s_close_n_21(sys, mesh, patch_name, grad_n)
  return internal.patch_s_close_n(sys, mesh, patch_name, grad_n)
end
local function patch_s_close_r_21(sys, mesh, patch_name, a, b, c)
  return internal.patch_s_close_r(sys, mesh, patch_name, a, b, c)
end
local function new_solver_cg_jac(sys, phi, tol, pool_cw)
  return internal.new_solver_cg_jac(sys, phi, tol, pool_cw)
end
local function new_solver_cg_dic(sys, phi, tol, pool_cw)
  return internal.new_solver_cg_dic(sys, phi, tol, pool_cw)
end
local function new_solver_bicgstab_jac(sys, phi, tol, pool_cw)
  return internal.new_solver_bicgstab_jac(sys, phi, tol, pool_cw)
end
local function new_solver_bicgstab_dilu(sys, phi, tol, pool_cw)
  return internal.new_solver_bicgstab_dilu(sys, phi, tol, pool_cw)
end
local function new_solver_gmres_dilu(sys, phi, tol, pool_cw, restart)
  return internal.new_solver_gmres_dilu(sys, phi, tol, restart, pool_cw)
end
return {["new-fvsys"] = new_fvsys, ["face-interp!"] = face_interp_21, ["face-normal-cw!"] = face_normal_cw_21, ["laplacian-k!"] = laplacian_k_21, ["div-uds-k!"] = div_uds_k_21, ["su-v-k!"] = su_v_k_21, ["patch-s-close-d!"] = patch_s_close_d_21, ["patch-s-close-n!"] = patch_s_close_n_21, ["patch-s-close-r!"] = patch_s_close_r_21, ["new-solver-cg-jac"] = new_solver_cg_jac, ["new-solver-cg-dic"] = new_solver_cg_dic, ["new-solver-bicgstab-jac"] = new_solver_bicgstab_jac, ["new-solver-bicgstab-dilu"] = new_solver_bicgstab_dilu, ["new-solver-gmres-dilu"] = new_solver_gmres_dilu}
