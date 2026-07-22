;; (demo_chasm) ; simple demo of CHASM for FVM

(local {: fvm &as nb} (require :nabla))

(local asm (fvm.chasm.new :laplace))

(let [su (asm:const :su 3)
      phi (asm:scalar_prog :phi)
      U (asm:vector_reg :U)
      Un (asm:scalar_reg_fw :Un)]
  (print "need to add asm:main!"))
