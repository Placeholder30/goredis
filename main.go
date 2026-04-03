package main

import (
	"github.com/placeholder30/gredis/store"
)

func main() {
	goRedis := store.NewStorage()
	err := goRedis.Init()
	if err != nil {
		panic(err)
	}

	err = (goRedis.Deint())
	if err != nil {
		panic(err)
	}

}
