const std = @import("std");
const Io = std.Io;

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
        std.log.info("server is listening on address={s} port={d}", .{ self.host, self.port });
        return try self.address.listen(io, .{
            .mode = .stream,
            .protocol = .tcp,
        });
    }
};
