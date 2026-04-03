package main

import (
	"sync"
)

type Storage struct {
	mu  sync.Mutex
	mem map[string]any
}

func newStorage() *Storage {
	return &Storage{
		mem: make(map[string]any),
	}
}

func (s *Storage) GET(item string) any {
	val, ok := s.mem[item]
	if ok {
		return val
	}
	return nil
}
func (s *Storage) SET(key string, value any) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.mem[key] = value
	return "OK"
}
func (s *Storage) DEL(keys ...string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	deleteCount := 0
	for _, key := range keys {
		_, ok := s.mem[key]
		if !ok {
			continue
		}
		delete(s.mem, key)
		deleteCount++
	}
	return deleteCount
}

type store interface {
	GET(item string) any
	SET(key, value string) string
	DEL(key string) int
}

func main() {
	_ = newStorage()

}
