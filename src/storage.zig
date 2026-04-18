const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Mutex = std.Io.Mutex;
const Entry = @import("entry.zig").Entry;
const EntryValue = @import("entry.zig").EntryValue;
const Op = @import("entry.zig").Op;
const log = std.log.scoped(.store);
const assert = std.debug.assert;
pub const Storage = struct {
    allocator: Allocator,
    io: Io,
    mem: std.StringHashMap([]u8),
    expiryMap: std.StringHashMap([]u8),
    aof: Io.File,
    writer: Io.File.Writer,

    pub fn init(alloc: Allocator, io: Io, aof: Io.File, writer: Io.File.Writer) Storage {
        return .{
            .allocator = alloc,
            .io = io,

            .mem = std.StringHashMap([]u8).init(alloc),
            .expiryMap = std.StringHashMap([]u8).init(alloc),
            .aof = aof,
            .writer = writer,
        };
    }
    pub fn deinit(self: *Storage) void {
        var it = self.mem.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.mem.deinit();
        var ex_it = self.expiryMap.iterator();
        while (ex_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.expiryMap.deinit();
    }
    pub fn set(self: *Storage, entry: Entry) ![]const u8 {
        const encoded_res = try encode(self.allocator, entry);
        const stats = try self.writer.file.stat(self.io);

        // TODO  configurable flushing to reduce sys calls we can implement tx with this.
        try self.aof.writePositionalAll(self.io, encoded_res, stats.size);
        const key = try self.allocator.dupe(u8, entry.key);
        if (self.mem.fetchRemove(key)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }
        try self.mem.put(key, encoded_res);
        return "ok";
    }

    pub fn get(self: *Storage, key: []const u8) !?Entry {
        const maybe_val = self.mem.get(key);
        if (maybe_val) |value| {
            return try self.decode(value);
        }
        return null;
    }

    pub fn del(self: *Storage, entry: Entry) ![]const u8 {
        const val = try encode(self.allocator, entry); // entry = arenallocation
        const stats = try self.aof.stat(self.io);
        try self.aof.writePositionalAll(self.io, val, stats.size);
        const maybe_kv = self.mem.fetchRemove(entry.key);
        if (maybe_kv) |kv| {
            self.allocator.free(kv.value);
            self.allocator.free(kv.key);
            return "ok";
        }
        return "err";
    }

    pub fn expire(self: *Storage, entry: Entry) ![]const u8 {
        const val = try encode(self.allocator, entry);
        const pos = try self.aof.stat(self.io);
        try self.aof.writePositionalAll(self.io, val, pos.size);
        try self.expiryMap.put(entry.key, val);
        return "ok";
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
    /// del -> [op][keylen][key]
    /// expire ->[op][tag][key_len][value_len][key][value]
    ///
    /// entry:Entry is allocated with an arena and will be freed at the end of the request so duplicate long lived items
    pub fn encode(alloc: Allocator, entry: Entry) ![]u8 {
        const key = entry.key;
        const op = entry.op;
        const opInt: u8 = @intFromEnum(op);
        if (op == .del) {
            var buffer = try alloc.alloc(u8, 1 + 4 + key.len);
            buffer[0] = opInt;
            const key_len: u32 = @intCast(key.len);
            std.mem.writeInt(u32, buffer[1..5], key_len, .little);
            @memcpy(buffer[5..][0..key_len], key);
            return buffer;
        }
        const value_tag: u8 = @intFromEnum(entry.value.?);
        assert(entry.value != null);
        const entryValue = entry.value orelse unreachable;
        const encoded_value = switch (entryValue) {
            .string => |s| try alloc.dupe(u8, s),
            .int => |i| try alloc.dupe(u8, std.mem.asBytes(&i)),
            .boolean => |b| try alloc.dupe(u8, &[_]u8{if (b) 1 else 0}),
            .float => |f| try alloc.dupe(u8, std.mem.asBytes(&f)),
        };

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
                @memcpy(buffer[10..][0..key.len], key);
                @memcpy(buffer[10 + key.len ..], encoded_value);
                return buffer;
            },
        }
    }
    pub fn parseRequest(_: Storage, alloc: std.mem.Allocator, msg: []const u8) !Entry {
        const raw_json = try std.json.parseFromSliceLeaky(RawEntry, alloc, msg, .{ .parse_numbers = true, .ignore_unknown_fields = true });

        const raw_op = raw_json.op;
        const raw_value = raw_json.value;
        const op = std.meta.stringToEnum(Op, raw_op) orelse
            return error.InvalidOperation;

        if ((op == .set or op == .expire) and raw_value == null) return error.ValueRequired;
        const key = raw_json.key;
        log.debug("parsed key->{s} \n", .{key});
        const query = blk: switch (op) {
            .get, .del => Entry.init(op, key, null),
            .set, .expire => {
                assert(raw_value != null);
                const value = raw_json.value orelse unreachable;
                const entry_value = try parseEntryValue(value);
                break :blk Entry.init(op, key, entry_value);
            },
        };
        log.debug("parsed obj={any}> \n", .{query});
        return query;
    }
    fn parseEntryValue(value: std.json.Value) !EntryValue {
        const entry_value = switch (value) {
            .bool => EntryValue{ .boolean = value.bool },
            .integer => EntryValue{ .int = value.integer },
            .float => EntryValue{ .float = value.float },
            .string => EntryValue{ .string = value.string },
            else => {
                return error.UnsupportedDataType;
            },
        };
        return entry_value;
    }

    pub fn replayLog(self: *Storage) !void {
        log.warn("replaying append only log\n", .{});
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
                        const timestamp_bytes = buff[header.len + key.len ..];
                        const expiry_time = std.mem.bytesToValue(i64, timestamp_bytes);
                        if (getCurrentTime(self.io).toMilliseconds() > expiry_time) {
                            self.allocator.free(key);
                            self.allocator.free(buff);
                            continue;
                        } //don't build map if already expired
                        try self.expiryMap.put(key, buff);
                        log.debug("exp -> key={s} val={any}\n", .{ key, buff });
                    } else {
                        log.debug("set -> key= {s} val={any}", .{ key, buff });
                        if (self.mem.fetchRemove(key)) |old| {
                            self.allocator.free(old.key);
                            self.allocator.free(old.value);
                        }
                        try self.mem.put(key, buff);
                    }
                },
                .del => {
                    const header = try reader.interface.readAlloc(self.allocator, 5);
                    defer self.allocator.free(header);
                    const key_bytes = header[1..5];
                    const key_len = std.mem.bytesToValue(u32, key_bytes);

                    const key = try reader.interface.readAlloc(self.allocator, key_len);
                    defer self.allocator.free(key);

                    log.debug("del key-> {s}<-\n", .{key});
                    _ = self.mem.remove(key);
                },
                .get => unreachable, // we never write gets to the aof
            }
        }
    }
};

pub fn getCurrentTime(io: Io) std.Io.Timestamp {
    const time_stamp: std.Io.Timestamp = .now(io, .real);
    return time_stamp;
}

const RawEntry = struct {
    op: []const u8 = "",
    key: []const u8,
    value: ?std.json.Value = null,
};
