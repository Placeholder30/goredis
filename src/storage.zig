const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Mutex = std.Io.Mutex;
const Entry = @import("entry.zig").Entry;
const EntryValue = @import("entry.zig").EntryValue;
const Op = @import("entry.zig").Op;

pub const Storage = struct {
    allocator: Allocator,
    io: Io,
    mutex: *std.Io.Mutex,
    mem: std.StringHashMap([]u8),
    expiryMap: std.StringHashMap([]u8),
    aof: Io.File,

    pub fn init(alloc: Allocator, io: Io, mutex: *Mutex, aof: Io.File) Storage {
        return .{
            .allocator = alloc,
            .io = io,
            .mutex = mutex,
            .mem = std.StringHashMap([]u8).init(alloc),
            .expiryMap = std.StringHashMap([]u8).init(alloc),
            .aof = aof,
        };
    }

    pub fn replayLog(self: *Storage) !void {
        var buffer: [1]u8 = undefined;
        var reader = self.aof.reader(self.io, &buffer);
        while (true) {
            const meta_data = try reader.interface.takeByte();
            const op: Op = @enumFromInt(meta_data);
            reader.interface.seek -= 1;
            switch (op) {
                .set, .expire => {
                    const header = try reader.interface.readAlloc(self.allocator, 10);
                    defer self.allocator.free(header);
                    const key_bytes = header[2..6];
                    const value_bytes = (header[6..10]);
                    const key_len = std.mem.bytesToValue(u32, key_bytes);
                    const value_len = std.mem.bytesToValue(u32, value_bytes);

                    const body = try reader.interface.readAlloc(self.allocator, key_len + value_len);
                    defer self.allocator.free(body);

                    const key = try self.allocator.dupe(u8, body[0..key_len]);
                    var buff = try self.allocator.alloc(u8, header.len + body.len);
                    @memcpy(buff[0..header.len], header);
                    @memcpy(buff[header.len..], body);
                    if (op == .expire) {
                        try self.expiryMap.put(key, buff);
                        std.debug.print("expire -> {s}\n", .{key});
                        std.debug.print("expire -> {any}\n", .{buff});
                    } else {
                        std.debug.print("set -> {s}\n", .{key});
                        std.debug.print("set -> {any}\n", .{buff});
                        try self.mem.put(key, buff);
                    }
                },
                .del => {
                    const header = try reader.interface.readAlloc(self.allocator, 5);
                    defer self.allocator.free(header);
                    const key_bytes = header[1..5];
                    const key_len = std.mem.bytesToValue(u32, key_bytes);

                    std.debug.print("del -> {d}\n", .{key_len});
                    const key = try reader.interface.readAlloc(self.allocator, key_len);
                    defer self.allocator.free(key);

                    std.debug.print("del key-> {s}<-\n", .{key});
                    _ = self.mem.remove(key);
                },
                .get => unreachable,
            }
        }
    }

    pub fn deinit(self: *Storage) void {
        var it = self.mem.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.mem.deinit();
        var ex_it = self.expiryMap.iterator();
        while (ex_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.expiryMap.deinit();
    }

    pub fn set(self: *Storage, entry: Entry) !void {
        const encoded_res = try encode(self.allocator, entry);
        const stats = try self.aof.stat(self.io);
        try self.aof.writePositionalAll(self.io, encoded_res, stats.size);
        try self.mem.put(entry.key, encoded_res);
    }

    pub fn get(self: *Storage, key: []const u8) !?Entry {
        const maybe_val = self.mem.get(key);
        if (maybe_val) |value| {
            return try self.decode(value);
        }
        return null;
    }

    pub fn del(self: *Storage, entry: Entry) !bool {
        const val = try encode(self.allocator, entry);
        const stats = try self.aof.stat(self.io);
        try self.aof.writePositionalAll(self.io, val, stats.size);
        return self.mem.remove(entry.key);
    }

    pub fn expire(self: *Storage, entry: Entry) !void {
        const val = try encode(self.allocator, entry);
        const pos = try self.aof.stat(self.io);
        try self.aof.writePositionalAll(self.io, val, pos.size);
        try self.expiryMap.put(entry.key, val);
    }

    pub fn decode(self: *Storage, encoded_text: []u8) !?Entry {
        const header = encoded_text;
        const op: Op = @enumFromInt(header[0]);
        if (op == .del) {
            const key = try self.allocator.dupe(u8, header[5..]);
            return .{
                .op = .del,
                .key = key,
                .value = null,
            };
        }
        const tag: std.meta.Tag(EntryValue) = @enumFromInt(header[1]);
        const key_len = std.mem.readInt(u32, header[2..6], .little);
        // const value_len = std.mem.readInt(u32, header[6..10], .little);

        const key = header[10..][0..key_len];
        const value = header[10 + key_len ..];
        const entryValue: EntryValue = switch (tag) {
            .boolean => .{ .boolean = header[0] == 1 },
            .string => .{ .string = value },
            .float => .{ .float = std.mem.bytesToValue(f64, value) },
            .int => .{ .int = std.mem.bytesToValue(i64, value) },
        };
        return Entry{
            .key = key,
            .op = op,
            .value = entryValue,
        };
    }

    ///set -> [op][tag][keylen][value_len][key][value]
    ///
    /// del -> [op][keylen][key]
    ///
    /// expire ->[op][tag][key_len][value_len][key][value]
    pub fn encode(alloc: Allocator, entry: Entry) ![]u8 {
        const key = entry.key;
        const op = entry.op;
        const opInt: u8 = @intFromEnum(op);
        if (op == .del) {
            var buffer = try alloc.alloc(u8, 1 + 4 + key.len);
            buffer[0] = opInt;
            const key_len: u32 = @intCast(key.len);
            std.mem.writeInt(u32, buffer[1..5], key_len, .little);
            const key_dup = try alloc.dupe(u8, key);
            @memcpy(buffer[5..][0..key_len], key_dup);
            return buffer;
        }
        const value_tag: u8 = @intFromEnum(entry.value.?);

        const entryValue = entry.value orelse unreachable;
        const encoded_value = switch (entryValue) {
            .string => |s| try alloc.dupe(u8, s),
            .int => |i| try alloc.dupe(u8, std.mem.asBytes(&i)),
            .boolean => |b| try alloc.dupe(u8, &[_]u8{if (b) 1 else 0}),
            .float => |f| try alloc.dupe(u8, std.mem.asBytes(&f)),
        };
        const key_dup = try alloc.dupe(u8, key);
        defer alloc.free(key_dup);
        defer alloc.free(encoded_value);
        const key_len: u32 = @intCast(key.len);
        const value_len: u32 = @intCast(encoded_value.len);

        switch (op) {
            .del => {
                unreachable;
            },
            else => {
                const buffer_layout_total = 1 + 1 + 4 + 4 + key_len + value_len;
                var buffer = try alloc.alloc(u8, buffer_layout_total);
                buffer[0] = opInt;
                buffer[1] = value_tag;
                std.mem.writeInt(u32, buffer[2..6], key_len, .little);
                std.mem.writeInt(u32, buffer[6..10], value_len, .little);
                @memcpy(buffer[10..][0..key.len], key_dup);
                @memcpy(buffer[10 + key.len ..], encoded_value);
                return buffer;
            },
        }
    }
};
