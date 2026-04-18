# Zedis

A lightweight, Redis-like storage engine written in Zig.

## Features

- Key-value storage with support for strings, integers, floats, and booleans
- Append-only log (AOF) for persistence and crash recovery
- Key expiry support
- HTTP interface for queries
- Fast in-memory reads

## Commands

| Command  | Description                     | Example                                      |
|----------|---------------------------------|----------------------------------------------|
| `SET`    | Store a value                   | `{ "op": "SET", "key": "name", "value": 22 }`|
| `GET`    | Retrieve a value                | `{ "op": "GET", "key": "name" }`             |
| `DEL`    | Delete a key                    | `{ "op": "DEL", "key": "name" }`             |
| `EXPIRE` | Store a value with an expiry    | `{ "op": "EXPIRE", "key": "name", "value": ${milliseconds since epoch} }`|

## Usage

Queries are sent as JSON over HTTP:

```sh
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{ "op": "SET", "key": "fave_anime", "value": "one piece" }'
```

## Building

```sh
zig build
```