package main

import (
	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
	"fmt"
	"flag"
	"encoding/json"
)

func main() {
	flag.Parse()
	filename := flag.Arg(0)

	lispCtx := jnlisp.NewContext()
	blocks, err := lispCtx.LoadFromFile(filename)
	if err != nil {
		fmt.Println(err)
		return
	}

	jsonData, _ := json.Marshal(blocks)

	fmt.Printf("%v", string(jsonData))
}
