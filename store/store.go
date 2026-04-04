package store

import (
	"bufio"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

type WriteAheadLog os.File
type Op byte
type Type byte

type Storage struct {
	mu            sync.RWMutex
	mem           map[string][]byte
	expiryMap     map[string]time.Duration
	writeAheadLog *os.File
}

const (
	GET Op = iota + 1
	DEL
	SET
	EXPIRE
)
const (
	STRING Type = iota + 1
	BOOLEAN
	INTEGER
	// LIST
	// HASH
	// SETS
)

// [Op][Type][keylen][valueLen][key][value]
type Entry struct {
	Op         Op
	typ        Type
	key        []byte
	value      []byte
	expiryTime time.Duration
}

func DecodeDel(r io.Reader) (*Entry, error) {

	header := make([]byte, 4)
	_, err := io.ReadFull(r, header)
	if err != nil {

		return nil, err
	}
	keylen := binary.LittleEndian.Uint32(header[0:4])
	key := make([]byte, keylen)
	_, err = io.ReadFull(r, key)
	return &Entry{
		Op:  DEL,
		key: key,
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
	case EXPIRE:
		entry, err = DecodeExpiry(r)
		return entry, nil, true
	default:
		return nil, nil, false
	}

	//consider returning nil here so we know to delete map

}

func NewStorage() *Storage {
	return &Storage{
		mem:       make(map[string][]byte),
		expiryMap: make(map[string]time.Duration),
	}
}
func (s *Storage) ReplayLog() error {
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
		fmt.Println(mem)
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
	s.mu.RLock()
	defer s.mu.RUnlock()
	val, ok := s.mem[item]
	if ok {
		return val
	}
	return nil
}

func (s *Storage) SET(key, value []byte, expiry time.Duration) (string, error) {
	var hasExpiry bool
	expiryTime := expiry.Nanoseconds()
	if expiryTime != 0 {
		currentTime := time.Now().UnixNano()
		if currentTime > expiry.Nanoseconds() {
			return "", errors.New("Invalid time")
		}
		s.expiryMap[string(key)] = expiry
		hasExpiry = true
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	entry := Entry{Op: SET, key: []byte(key), value: []byte(value)}
	val := entry.EncodeSet()
	_, err := s.writeToWAL(val)
	if err != nil {
		return "", err
	}

	if hasExpiry {
		entry := Entry{Op: EXPIRE, key: key, expiryTime: expiry}
		expiryText := entry.EncodeExpiry()
		_, err = s.writeToWAL([]byte(expiryText))
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

func (s *Storage) EXPIRE(key string, expiryTime time.Duration) (int, error) {
	if expiryTime == 0 {
		return 0, errors.New("invalid expiry")
	}
	entry := Entry{Op: EXPIRE, key: []byte(key), expiryTime: expiryTime}
	expiryText := entry.EncodeExpiry()
	_, err := s.writeToWAL([]byte(expiryText))
	if err != nil {
		return 0, errors.New("failed to write to wal")
	}
	return 1, nil
}

// Op-keylen-valuelen-k-v
func DecodeExpiry(r io.Reader) (*Entry, error) {
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
	valueSec := binary.LittleEndian.Uint32(value)
	return &Entry{Op: SET, key: key, expiryTime: time.Duration(valueSec)}, nil
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
	return &Entry{Op: SET, key: key, value: value}, nil
}

func (e *Entry) EncodeSet() []byte {
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

// TODO
// for expiry, value will be encoded using the expiry field.
func (e *Entry) EncodeExpiry() []byte {
	keylen := uint32(len(e.key))
	valueLen := uint32(len(e.expiryTime.String())) //FIXME
	buffer := make([]byte, 0)
	buffer = append(buffer, byte(e.Op))

	temp := make([]byte, 4)
	binary.LittleEndian.PutUint32(temp, keylen)
	buffer = append(buffer, temp...)
	binary.LittleEndian.AppendUint32(temp, valueLen)
	buffer = append(buffer, temp...)

	buffer = append(buffer, e.key...)
	buffer = append(buffer, byte(e.expiryTime))
	return buffer
}

func (s *Storage) writeToWAL(bytes []byte) (int, error) {

	written, err := s.writeAheadLog.Write(bytes)
	if err != nil {
		return 0, err
	}

	return written, nil
}
