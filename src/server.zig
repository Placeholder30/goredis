const std = @import("std");
const Io = std.Io;
const Storage = @import("storage.zig").Storage;
const http = std.http;
const EntryValue = @import("entry.zig").EntryValue;
const log = std.log.scoped(.server);
pub const Server = struct {
    host: []const u8,
    port: u16 = 8080,
    address: std.Io.net.IpAddress,
    io: Io,

    const Self = @This();

    pub fn init(io: Io, host: []const u8, port: u16) !Server {
        return .{
            .host = host,
            .io = io,
            .port = port,
            .address = try std.Io.net.IpAddress.parse(host, port),
        };
    }

    pub fn listen(self: Self, io: Io) !Io.net.Server {
        log.info("server is listening on address={s} port={d}", .{ self.host, self.port });
        return try self.address.listen(io, .{
            .mode = .stream,
            .protocol = .tcp,
        });
    }
};

pub fn handleRequest(io: Io, connection: Io.net.Stream, storage: *Storage) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.smp_allocator);
    defer arena.deinit();
    const alloca = arena.allocator();

    var reader_buff: [4096]u8 = undefined;
    var writer_buff: [4096]u8 = undefined;
    var write = connection.writer(io, &writer_buff);
    const out = &write.interface;

    var connection_reader = connection.reader(io, &reader_buff);
    const in = &connection_reader.interface;
    var serv: http.Server = .init(in, out);
    const request = try serv.receiveHead();
    // _ = request;

    const content_length = request.head.content_length orelse return error.MissingContentLength;
    if (content_length == 0) return error.EmptyBody;

    const body = try in.take(content_length);
    const entry = try storage.parseRequest(alloca, body); // free eor
    switch (entry.op) {
        .del => {
            const res = try storage.del(entry);
            log.debug("{s}", .{res});
            try handleResponse(res, serv);
        },
        .expire => {
            const res = try storage.expire(entry);
            try handleResponse(res, serv);
        },
        .get => {
            const res = try storage.get(entry.key);
            if (res) |val| {
                try handleGetResponse(val.value.?, serv);
            } else try handleResponse("nil", serv);
        },
        .set => {
            const res = try storage.set(entry);
            try handleResponse(res, serv);
        },
    }
}

pub fn handleGetResponse(res: EntryValue, serv: http.Server) !void {
    try serv.out.print(
        "HTTP/1.1 200 OK\r\n" ++
            // "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n",
        .{},
    );
    _ = switch (res) {
        .boolean => |b| try serv.out.print("{}", .{b}),
        .float => |f| try serv.out.print("{}", .{f}),
        .int => |i| try serv.out.print("{}", .{i}),
        .string => |i| try serv.out.print("{s}", .{i}),
    };
    try serv.out.flush();
}

fn handleResponse(res: []const u8, serv: http.Server) !void {
    try serv.out.print(
        "HTTP/1.1 200 OK\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}\n",
        .{ res.len, res },
    );
    try serv.out.flush();
}
