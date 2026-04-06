const std = @import("std");
const Io = std.Io;
const log = std.log;
const Allocator = std.mem.Allocator;
const Mutex = std.Io.Mutex;
const builtin = @import("builtin");
pub const Op = enum {
    GET,
    SET,
    DEL,
    EXPIRE,
};

const Entry = struct {
    Op: Op,
    key: []const u8,
    value: EntryValue,
};

const EntryValue = union(enum) {
    string: []const u8,
    int: i64,
    boolean: bool,
    float: f64,

    /// encoding returns [op][tag][keylen][value_len][key]?[value]
    pub fn encode(self: EntryValue, alloc: Allocator, key: []const u8, op: Op) ![]u8 {
        const tag: u8 = @intFromEnum(self);
        const opInt: u8 = @intFromEnum(op);

        const encoded_value = switch (self) {
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
        //[op][tag][keylen][value_len][key]?[value]
        const buffer_layout_total = 1 + 1 + 4 + 4 + key_len + value_len;
        var buffer = try alloc.alloc(u8, buffer_layout_total);
        buffer[0] = opInt;
        buffer[1] = tag;
        std.mem.writeInt(u32, buffer[2..6], key_len, .little);
        std.mem.writeInt(u32, buffer[6..10], value_len, .little);
        @memcpy(buffer[10..][0..key.len], key_dup);
        @memcpy(buffer[10 + key.len ..], encoded_value);

        return buffer;
    }

    // fn decode(self: *EntryValue, alloc: Allocator, bytes: []u8) !EntryValue {}
};

const Storage = struct {
    allocator: Allocator,
    io: Io,
    mutex: *std.Io.Mutex,
    mem: std.StringHashMap([]u8),
    expiryMap: std.StringHashMap(i64),
    aof: Io.File,

    pub fn init(alloc: Allocator, io: Io, mutex: *Mutex, aof: Io.File) Storage {
        return .{
            .allocator = alloc,
            .io = io,
            .mutex = mutex,
            .mem = std.StringHashMap([]u8).init(alloc),
            .expiryMap = std.StringHashMap(i64).init(alloc),
            .aof = aof,
        };
    }

    pub fn deinit(self: *Storage) void {
        var it = self.mem.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.mem.deinit();
        self.expiryMap.deinit();
    }

    pub fn set(self: *Storage, entry: *Entry) !void {
        const encoded_res = try entry.value.encode(self.allocator, entry.key, entry.Op);
        try writer(self.io, self.aof, encoded_res);

        try self.mem.put(entry.key, encoded_res);
    }
    pub fn get(self: *Storage, key: []const u8) !?Entry {
        const maybe_val = self.mem.get(key);
        if (maybe_val) |value| {
            const header = value;
            const op: Op = @enumFromInt(header[0]);
            const tag: std.meta.Tag(EntryValue) = @enumFromInt(header[1]);

            const key_len = std.mem.readInt(u32, header[2..6], .little);
            _ = std.mem.readInt(u32, header[6..10], .little);

            const key_value = header[10 + key_len ..];
            const entryValue: EntryValue = switch (tag) {
                .boolean => .{ .boolean = header[0] == 1 },
                .string => .{ .string = key_value },
                .float => .{ .float = std.mem.bytesToValue(f64, key_value) },
                .int => .{ .int = std.mem.bytesToValue(i64, key_value) },
            };
            return Entry{
                .key = key,
                .Op = op,
                .value = entryValue,
            };
        }
        return null;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = if (builtin.mode == .Debug) true else false }) = .init;
    const allocator = gpa.allocator();
    var mutex: Mutex = .init;
    const cwd = std.Io.Dir.cwd();
    const aof = try cwd.openFile(io, "aof.log", .{ .mode = .read_write });
    var storage = Storage.init(allocator, io, &mutex, aof);
    const string: []const u8 = "malik";
    var entry = Entry{ .Op = .SET, .key = "name", .value = .{ .string = string } };
    try storage.set(&entry);
    _ = try storage.get("name");
}

fn writer(io: Io, file: Io.File, bytes: []u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(file, io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    const bytes_written = try stdout_writer.write(bytes);
    log.info("bytes written {d}\n", .{bytes_written});
    try stdout_writer.flush(); // Don't forget to flush!

}
const testing = std.testing;
test "get and put test" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var mutex = std.Io.Mutex.init;
    const cwd = std.Io.Dir.cwd();
    const aof = try cwd.openFile(io, "test.log", .{ .mode = .read_write });
    var store = Storage.init(alloc, io, &mutex, aof);
    var entry = Entry{ .key = "age", .value = EntryValue{ .int = 32 }, .Op = .GET };
    defer store.deinit();
    try store.set(&entry);
    const got = try store.get("age");
    const want: i64 = 32;
    if (got) |well| {
        try testing.expectEqual(want, well.value.int);
    }
}
