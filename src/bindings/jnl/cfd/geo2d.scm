(define-module (jnl cfd geo2d)
  #:export (my-fancy-helper
            ;; Nodes
            make-node-array
            node-array-len
            node-array-add
            node-array-find-nearest
            node-array-find-or-add
            node-array-get
            node-array-write
            ;; PSLG
            make-pslg
            pslg-nodes-len
            pslg-edges-len
            pslg-holes-len
            pslg-regions-len
            pslg-node-add
            pslg-node-find-nearest
            pslg-node-find-or-add
            pslg-node-get
            pslg-edge-add
            pslg-hole-add
            pslg-region-add
            pslg-write))

(define (my-fancy-helper)
  (display "yada yada yada\n"))
