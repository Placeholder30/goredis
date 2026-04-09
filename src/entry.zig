const std = @import("std");
const Io = std.Io;
const log = std.log;
const Allocator = std.mem.Allocator;
const Mutex = std.Io.Mutex;
const builtin = @import("builtin");
const Storage = @import("storage.zig").Storage;
pub const Op = enum {
    get,
    set,
    del,
    expire,
};
pub const Entry = struct {
    op: Op,
    key: []const u8,
    value: ?EntryValue,

    pub fn init(op: Op, key: []const u8, value: ?EntryValue) Entry {
        return .{
            .op = op,
            .key = key,
            .value = value,
        };
    }
};

pub const EntryValue = union(enum) {
    string: []const u8,
    int: i64,
    boolean: bool,
    float: f64,
};
