const std = @import("std");
const Io = std.Io;
const log = std.log;
const Allocator = std.mem.Allocator;
const Mutex = std.Io.Mutex;
const builtin = @import("builtin");
const Storage = @import("storage.zig").Storage;
pub const Op = enum {
    GET,
    SET,
    DEL,
    EXPIRE,
};
pub const Entry = struct {
    Op: Op,
    key: []const u8,
    value: EntryValue,
};

pub const EntryValue = union(enum) {
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
        switch (op) {
            .SET => {},
            .DEL => {},
            .GET => {},
            else => {},
        }
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

    // pub fn decode(self: *Storage, encoded_text: []u8) !?Entry {
    //     // const header = encoded_text;
    //     // const op: Op = @enumFromInt(header[0]);
    //     // const tag: std.meta.Tag(EntryValue) = @enumFromInt(header[1]);

    //     // const key_len = std.mem.readInt(u32, header[2..6], .little);
    //     // _ = std.mem.readInt(u32, header[6..10], .little);

    //     // const key_value = header[10 + key_len ..];
    //     // const entryValue: EntryValue = switch (tag) {
    //     //     .boolean => .{ .boolean = header[0] == 1 },
    //     //     .string => .{ .string = key_value },
    //     //     .float => .{ .float = std.mem.bytesToValue(f64, key_value) },
    //     //     .int => .{ .int = std.mem.bytesToValue(i64, key_value) },
    //     // };
    //     // return Entry{
    //     //     .key = key,
    //     //     .Op = op,
    //     //     .value = entryValue,
    //     // };
    // }
};
