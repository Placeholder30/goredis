package store

import (
	"bufio"
	"encoding/binary"
	"io"
	"os"
	"sync"
)

type WriteAheadLog os.File

type Storage struct {
	mu            sync.Mutex
	mem           map[string][]byte
	writeAheadLog *os.File
}
type Op byte

const (
	GET Op = iota + 1
	DEL
	SET
)

func (o Op) String() string {
	switch o {
	case GET:
		return "GET"
	case DEL:
		return "DEL"
	case SET:
		return "SET"
	default:
		return "UNKNOWN"
	}
}

type Entry struct {
	Op    Op
	typ   byte
	key   []byte
	value []byte
}

func DecodeDel(r io.Reader) (*Entry, error) {

	header := make([]byte, 4)
	_, err := io.ReadFull(r, header)
	if err != nil {

		return nil, err
	}
	keylen := binary.LittleEndian.Uint32(header[0:4])
	buffer := make([]byte, keylen)
	_, err = io.ReadFull(r, buffer)
	return &Entry{
		Op:  DEL,
		key: buffer,
	}, nil
}

func Decode(r io.Reader) (*Entry, error, bool) {
	operation := make([]byte, 1)
	_, err := io.ReadFull(r, operation)
	if err != nil {

		return nil, err, false
	}
	var entry *Entry
	op := Op(operation[0])

	switch op {
	case SET:
		entry, _ = DecodeSet(r)
		return entry, nil, false
	case DEL:
		entry, _ = DecodeDel(r)
		return entry, nil, true
	default:
		return nil, nil, false
	}

	//consider returning nil here so we know to delete map

}

func NewStorage() *Storage {
	return &Storage{
		mem: make(map[string][]byte),
	}
}
func (s *Storage) Init() error {
	f, err := os.OpenFile("wal.log", os.O_APPEND|os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		return err
	}

	s.writeAheadLog = f

	stats, err := s.writeAheadLog.Stat()
	if stats.Size() == 0 {
		return nil
	}
	if err != nil {
		return err
	}

	mem := s.mem

	reader := bufio.NewReader(s.writeAheadLog)
	for {
		entry, err, del := Decode(reader)
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		if !del {
			mem[string(entry.key)] = entry.value
		} else {
			delete(mem, string(entry.key))

		}
	}

	return nil
}
func (s *Storage) Deint() error {
	return (s.writeAheadLog.Close())
}

func (s *Storage) GET(item string) []byte {
	val, ok := s.mem[item]
	if ok {
		return val
	}
	return nil
}

func (s *Storage) SET(key, value []byte) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry := Entry{Op: SET, key: []byte(key), value: []byte(value)}
	val := entry.Encode()
	_, err := s.writeToWAL(val)
	if err != nil {
		return "", err
	}
	s.mem[string(key)] = value

	return "OK", nil
}

func (s *Storage) DEL(keys ...string) (int, error) {

	s.mu.Lock()
	defer s.mu.Unlock()
	deleteCount := 0
	for _, key := range keys {
		entry := Entry{Op: DEL, key: []byte(key)}
		_, ok := s.mem[key]
		if !ok {
			continue
		}
		bytes := entry.EncodeDel()

		_, err := s.writeToWAL(bytes)
		if err != nil {
			return 0, err
		}
		delete(s.mem, key)
		deleteCount++
	}
	return deleteCount, nil
}

type Store interface {
	GET(item string) any
	SET(key, value any) string
	DEL(key ...string) int
}

func (s *Storage) writeToWAL(bytes []byte) (int, error) {

	written, err := s.writeAheadLog.Write(bytes)
	if err != nil {
		return 0, err
	}

	return written, nil
}

func DecodeSet(r io.Reader) (*Entry, error) {
	header := make([]byte, 8)
	_, err := io.ReadFull(r, header)
	if err != nil {

		return nil, err
	}
	keylen := binary.LittleEndian.Uint32(header[0:4])
	valueLen := binary.LittleEndian.Uint32(header[4:8])

	key := make([]byte, keylen)
	_, err = io.ReadFull(r, key)
	if err != nil {
		return nil, err
	}

	value := make([]byte, valueLen)
	_, err = io.ReadFull(r, value)
	if err != nil {
		return nil, err
	}
	res := &Entry{Op: SET, key: key, value: value}

	return res, nil
}

func (e *Entry) Encode() []byte {
	keyLen := uint32(len(e.key))
	valueLen := uint32(len(e.value))

	buffer := make([]byte, 0)
	buffer = append(buffer, byte(e.Op))

	temp := make([]byte, 4)
	binary.LittleEndian.PutUint32(temp, keyLen)
	buffer = append(buffer, temp...)

	binary.LittleEndian.PutUint32(temp, valueLen)
	buffer = append(buffer, temp...)

	buffer = append(buffer, e.key...)
	buffer = append(buffer, e.value...)
	return buffer

}
func (e *Entry) EncodeDel() []byte {
	keyLen := uint32(len(e.key))
	buffer := make([]byte, 0)
	buffer = append(buffer, byte(e.Op))

	temp := make([]byte, 4)
	binary.LittleEndian.PutUint32(temp, keyLen)
	buffer = append(buffer, temp...)
	buffer = append(buffer, e.key...)
	return buffer
}
