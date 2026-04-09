const std = @import("std");
const Io = std.Io;
const log = std.log;
const Allocator = std.mem.Allocator;
const Mutex = std.Io.Mutex;
const builtin = @import("builtin");
const Storage = @import("storage.zig").Storage;
const Entry = @import("entry.zig").Entry;
const EntryValue = @import("entry.zig").EntryValue;
// const assert = std.debug.assert;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = if (builtin.mode == .Debug) true else false }) = .init;
    // defer assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var mutex: Mutex = .init;
    const cwd = std.Io.Dir.cwd();
    const aof = cwd.openFile(io, "aof.log", .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => try cwd.createFile(io, "aof", .{ .read = true, .truncate = false }),
        else => {
            return err;
        },
    };

    var storage = Storage.init(allocator, io, &mutex, aof);

    storage.replayLog() catch |err| switch (err) {
        error.EndOfStream => {},
        else => {
            return err;
        },
    };
    storage.deinit();
}

const testing = std.testing;
test "get and put test" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var mutex = std.Io.Mutex.init;
    const cwd = std.Io.Dir.cwd();
    const aof = try cwd.openFile(io, "test.log", .{ .mode = .read_write });

    var store = Storage.init(alloc, io, &mutex, aof);
    const entry = Entry{ .key = "age", .value = EntryValue{ .int = 32 }, .op = .get };
    defer store.deinit();
    try store.set(entry);
    const got = try store.get("age");
    const expected: i64 = 32;
    if (got) |well| {
        try testing.expectEqual(expected, well.value.?.int);
    }
}
