const std = @import("std");
const Io = std.Io;
const log = std.log;
const Allocator = std.mem.Allocator;
const Mutex = std.Io.Mutex;
const builtin = @import("builtin");
const Storage = @import("storage.zig").Storage;
const Entry = @import("entry.zig").Entry;
const EntryValue = @import("entry.zig").EntryValue;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = if (builtin.mode == .Debug) true else false }) = .init;
    const allocator = gpa.allocator();
    var mutex: Mutex = .init;
    const cwd = std.Io.Dir.cwd();
    const aof = try cwd.openFile(io, "aof.log", .{ .mode = .read_write });

    var storage = Storage.init(allocator, io, &mutex, aof);
    // const val: i64 = 1888888;
    // const entryVal = EntryValue{ .int = val };
    // const entry = Entry{ .key = "todo", .op = .expire, .value = entryVal };

    // try storage.set(entry);
    try storage.replayLog();

    // const res = try storage.get("todo");
    // if (res) |en| {
    //     std.debug.print("{s} -> \n", .{en.key});
    //     if (en.value) |valery| {
    //         std.debug.print("{any}", .{valery});
    //     }
    // }
}

pub fn writer(io: Io, file: Io.File, bytes: []u8) !void {
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
    const entry = Entry{ .key = "age", .value = EntryValue{ .int = 32 }, .op = .get };
    defer store.deinit();
    try store.set(entry);
    const got = try store.get("age");
    const expected: i64 = 32;
    if (got) |well| {
        try testing.expectEqual(expected, well.value.?.int);
    }
}
