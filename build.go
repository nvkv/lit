package main

import (
	"os"
	"os/exec"
)


func main() {
	_ = os.Mkdir("build", os.ModePerm)
	
	tangle := exec.Command("go", "run", "bootlit.go", "--src-out", "build/lit.go", "lit.go.w")
	err := tangle.Start()
	if err != nil {
		panic(err)
	}

	build := exec.Command("go", "build", "build/lit.go")
	err = build.Start()
	if err != nil {
		panic(err)
	}
}