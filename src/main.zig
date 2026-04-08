const std = @import("std");
const Io = std.Io;
const log = std.log;
const Allocator = std.mem.Allocator;
const Mutex = std.Io.Mutex;
const builtin = @import("builtin");
const Storage = @import("storage.zig").Storage;
const Entry = @import("entry.zig").Entry;
const EntryValue = @import("entry.zig").Value;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = if (builtin.mode == .Debug) true else false }) = .init;
    const allocator = gpa.allocator();
    var mutex: Mutex = .init;
    const cwd = std.Io.Dir.cwd();
    const aof = try cwd.openFile(io, "aof.log", .{ .mode = .read_write });
    var storage = Storage.init(allocator, io, &mutex, aof);
    const string: []const u8 = "malik";
    var entry = Entry{ .op = .set, .key = "name", .value = .{ .string = string } };
    try storage.set(&entry);
    _ = try storage.get("name");
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
    var entry = Entry{ .key = "age", .value = EntryValue{ .int = 32 }, .op = .get };
    defer store.deinit();
    try store.set(&entry);
    const got = try store.get("age");
    const expected: i64 = 32;
    if (got) |well| {
        try testing.expectEqual(expected, well.value.int);
    }
}
