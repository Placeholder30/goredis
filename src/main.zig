const std = @import("std");
const Io = std.Io;
const log = std.log;
const Allocator = std.mem.Allocator;
const Mutex = std.Io.Mutex;
const builtin = @import("builtin");
const Op = union(enum) {
    GET,
    SET,
    DEL,
    EXPIRE,
};

const Type = union(enum) {
    BOOLEAN,
    STRING,
    INTEGER,
};
const EntryValue = union(enum) {
    string: []u8,
    int: i64,
    boolean: bool,
    float: f64,
};

const Entry = struct {
    Op: Op,
    // type: Type,
    key: []u8,
    value: EntryValue,
};
const Storage = struct {
    allocator: Allocator,
    mutex: *std.Io.Mutex,
    mem: std.StringHashMap([]u8),
    expiryMap: std.StringHashMap(i64),
    aof: Io.File,

    pub fn init(alloc: Allocator, mutex: *Mutex, aof: Io.File) Storage {
        return .{
            .allocator = alloc,
            .mutex = mutex,
            .mem = std.StringHashMap([]u8).init(alloc),
            .expiryMap = std.StringHashMap(i64).init(alloc),
            .aof = aof,
        };
    }

    pub fn deinit(self: *Storage) !void {
        const it = self.mem.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr);
            self.allocator.free(entry.value_ptr);
        }
        try self.mem.deinit();
        try self.expiryMap.deinit();
    }

    pub fn set(self: *Storage, key: []const u8, value: EntryValue, expiry_time: ?bool) !void {
        const key_dupe = try self.allocator.dupe(u8, key);
        const value_dupe = try self.allocator.dupe(@TypeOf(value), value);
        log.debug("{s}, {s}", .{ key_dupe, value_dupe });
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = if (builtin.mode == .Debug) true else false }) = .init;
    const allocator = gpa.allocator();
    var mutex: Mutex = .init;
    const cwd = std.Io.Dir.cwd();
    const aof = try cwd.openFile(io, "aof.log", .{ .mode = .read_write });
    var storage = Storage.init(allocator, &mutex, aof);
    try storage.set("z", "al", null);
}

// var stdout_buffer: [1024]u8 = undefined;
// var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
// const stdout_writer = &stdout_file_writer.interface;
// const time = std.Io.Timestamp.now(io, .real);
// _ = try stdout_writer.write("hello world bishes\n");
// log.debug("{d}", .{time.toSeconds()});
// try stdout_writer.flush(); // Don't forget to flush!
