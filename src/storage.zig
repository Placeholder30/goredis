const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Mutex = std.Io.Mutex;
const Entry = @import("entry.zig").Entry;
const EntryValue = @import("entry.zig").EntryValue;
const writer = @import("main.zig").writer;
const Op = @import("entry.zig").Op;

pub const Storage = struct {
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

    // pub fn replayLog(alloc Allocator, io:Io, aof:Io.File)!void{

    // }

    pub fn deinit(self: *Storage) void {
        var it = self.mem.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.mem.deinit();
        self.expiryMap.deinit();
    }

    pub fn set(self: *Storage, entry: *Entry) !void {
        const encoded_res = try entry.value.encode(self.allocator, entry.key, entry.op);
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
                .op = op,
                .value = entryValue,
            };
        }
        return null;
    }
};
