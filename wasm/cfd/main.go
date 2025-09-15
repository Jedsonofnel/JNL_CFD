//go:build wasm
package main

import (
	"syscall/js"
)

func main() {
	done := make(chan struct{})

	js.FuncOf(func(this js.Value, args []js.Value) any {
		name := args[0].String()
		Test(name)
		return nil
	})

	println("HELLO WORLD")

	<-done
}

func Test(name string) {
	println("HELLO " + name)
}
