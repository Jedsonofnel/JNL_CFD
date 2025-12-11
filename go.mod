module github.com/Jedsonofnel/jnlcfd

go 1.24.7

require (
	github.com/cbroglie/mustache v1.4.0
	jedn.dev/jnlisp v0.0.0-00010101000000-000000000000
)

replace jedn.dev/jnlisp => ../jnlisp

require (
	golang.org/x/sys v0.37.0 // indirect
	golang.org/x/term v0.36.0 // indirect
)
