package main

import (
	"encoding/json"
	"flag"
	"fmt"

	_ "github.com/Jedsonofnel/jnlcfd/internal/cfd/fvm"
	_ "github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

var ctx *jnlisp.Context

func init() {
	ctx = jnlisp.NewContext()
	ctx.ImportLibrary("cfd/fvm", "")
	ctx.ImportLibrary("cfd/geometry", "")
}

func main() {
	flag.Parse()
	filename := flag.Arg(0)

	blocks, err := ctx.LoadFromFile(filename)
	if err != nil {
		fmt.Println(err)
		return
	}

	jsonData, _ := json.Marshal(blocks)

	fmt.Printf("%v", string(jsonData))
}
