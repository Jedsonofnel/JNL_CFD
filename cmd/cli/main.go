package main

import (
	"encoding/json"
	"flag"
	"fmt"

	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

var ctx *jnlisp.Context

func init() {
	ctx = jnlisp.NewContext()
}

func main() {
	flag.Parse()
	filename := flag.Arg(0)

	blocks, err := ctx.EvalFile(filename)

	if err != nil {
		fmt.Println(err)
		return
	}

	jsonData, _ := json.Marshal(blocks)

	fmt.Printf("%v", string(jsonData))
}
