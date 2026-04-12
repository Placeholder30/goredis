const std = @import("std");
const Io = std.Io;
const log = std.log;
const Allocator = std.mem.Allocator;
const Mutex = std.Io.Mutex;
const builtin = @import("builtin");
const Storage = @import("storage.zig").Storage;
const Entry = @import("entry.zig").Entry;
const EntryValue = @import("entry.zig").EntryValue;
const Server = @import("server.zig").Server;
// const assert = std.debug.assert;

pub fn main(_: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = if (builtin.mode == .Debug) true else false }) = .init;
    // defer assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    var threaded_io: Io.Threaded = .init(alloc, .{});
    const io = threaded_io.io();
    const cwd = std.Io.Dir.cwd();
    const aof = cwd.openFile(io, "aof.log", .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => try cwd.createFile(io, "aof", .{ .read = true, .truncate = false }),
        else => {
            return err;
        },
    };
    // const now = std.Io.Clock.real.now(io).addDuration(.fromSeconds(5000)).toSeconds();
    var writer_buff: [4096]u8 = undefined;
    const writer: std.Io.File.Writer = .init(aof, io, &writer_buff);

    var storage = Storage.init(allocator, io, aof, writer);
    try storage.set(.{ .key = "do", .op = .set, .value = .{ .string = "hello world" } });
    defer storage.deinit();

    // storage.replayLog() catch |err| switch (err) {
    //     error.EndOfStream => {},
    //     else => {
    //         return err;
    //     },
    // };
    // try startServer(io);

}
fn startServer(io: Io) !void {
    const server = try Server.init(io, "127.0.0.1", 8080);

    var listener = try server.listen(io);
    while (true) {
        var connection = try listener.accept(io);
        defer connection.close(io);
        var write = connection.writer(io, &.{});
        _ = &write.interface;
    }
}

const alloc = std.testing.allocator;
const testing = std.testing;

test "set and get returns stored value" {
    const io = testing.io;
    const cwd = std.Io.Dir.cwd();

    const aof = try cwd.openFile(io, "test.log", .{ .mode = .read_write });

    var store = Storage.init(alloc, io, aof);
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
    const cwd = std.Io.Dir.cwd();

    const aof = try cwd.openFile(io, "test.log", .{ .mode = .read_write });

    var store = Storage.init(alloc, io, aof);
    defer store.deinit();

    const value = EntryValue{ .string = "iphone" };
    const set_entry = Entry.init(.set, "phone", value);

    try store.set(set_entry);
    const result = try store.get("phone");

    try std.testing.expect(result != null);
    try std.testing.expectEqualSlices(u8, "phone", result.?.key);
    try std.testing.expectEqualSlices(u8, "iphone", result.?.value.?.string);
}
