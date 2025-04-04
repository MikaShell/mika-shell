package main

import (
	"log"
	"os"
)

var assets string

func main() {
	if err := NewCli().Run(os.Args); err != nil {
		log.Fatal(err)
	}
}
