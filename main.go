package main

import (
	"time"

	"github.com/placeholder30/gredis/store"
)

func main() {
	goRedis := store.NewStorage()
	err := goRedis.ReplayLog()
	if err != nil {
		panic(err)
	}
	var futureTime time.Duration = time.Duration(time.Now().Add(time.Hour).UnixNano())
	_, err = goRedis.SET([]byte("age"), []byte("22"), futureTime)

	err = (goRedis.Deint())
	if err != nil {
		panic(err)
	}

}

type Store interface {
	GET(item string) any
	SET(key, value any) string
	DEL(key ...string) int
}
