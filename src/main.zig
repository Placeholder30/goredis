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
    // defer storage.deinit();
    storage.replayLog() catch |err| switch (err) {
        error.EndOfStream => {},
        else => {
            return err;
        },
    };
}

const alloc = std.testing.allocator;
const testing = std.testing;

test "set and get returns stored value" {
    const io = testing.io;
    var mutex = std.Io.Mutex.init;
    const cwd = std.Io.Dir.cwd();

    const aof = try cwd.openFile(io, "test.log", .{ .mode = .read_write });

    var store = Storage.init(alloc, io, &mutex, aof);
    defer store.deinit();

    const key = "ogunfe";
    const value: i64 = 3;
    const entry = Entry{
        .key = key,
        .value = EntryValue{ .int = value },
        .op = .set,
    };

    try store.set(entry);
    const result = try store.get(key);

    try testing.expect(result != null);

    const got = result.?;
    try testing.expect(got.value != null);
    try testing.expectEqual(value, got.value.?.int);
}

test "del" {
    const io = std.testing.io;
    var mutex = std.Io.Mutex.init;
    const cwd = std.Io.Dir.cwd();

    const aof = try cwd.openFile(io, "test.log", .{ .mode = .read_write });

    var store = Storage.init(alloc, io, &mutex, aof);
    defer store.deinit();

    const value = EntryValue{ .string = "iphone" };
    const set_entry = Entry.init(.set, "phone", value);

    try store.set(set_entry);
    const result = try store.get("phone");

    try std.testing.expect(result != null);
    try std.testing.expectEqualSlices(u8, "phone", result.?.key);
    try std.testing.expectEqualSlices(u8, "iphone", result.?.value.?.string);
}
