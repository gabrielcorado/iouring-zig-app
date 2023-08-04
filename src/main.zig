const std = @import("std");
const os = std.os;
const net = std.net;
const fmt = std.fmt;
const linux = os.linux;
const IO_Uring = linux.IO_Uring;
const print = std.debug.print;

var raw_buffers: [5][128]u8 = undefined;
var buffers = [2]os.iovec{
    .{ .iov_base = &raw_buffers[0], .iov_len = 128 },
    .{ .iov_base = &raw_buffers[1], .iov_len = 128 },
};

const connInfo = packed struct {
    fd: u32 = 0,
    type: enum(u16) {
        UNKNOWN,
        ACCEPT,
        READ,
        WRITE,
        CLOSE,
    } = .UNKNOWN,
    _: u16 = 0,

    pub fn accept(fd: os.socket_t) connInfo {
        return connInfo{
            .fd = @intCast(fd),
            .type = .ACCEPT,
        };
    }

    pub fn read(fd: os.socket_t) connInfo {
        return connInfo{
            .fd = @intCast(fd),
            .type = .READ,
        };
    }

    pub fn write(fd: os.socket_t) connInfo {
        return connInfo{
            .fd = @intCast(fd),
            .type = .WRITE,
        };
    }

    pub fn close() connInfo {
        return connInfo{ .type = .CLOSE };
    }

    pub fn empty() connInfo {
        return connInfo{};
    }

    pub fn cast(self: connInfo) u64 {
        return @bitCast(self);
    }
};

pub fn main() !void {
    var ring = try IO_Uring.init(16, 0);
    defer ring.deinit();

    const localhost = try net.Address.parseIp("127.0.0.1", 8080);
    var server = net.StreamServer.init(.{});
    defer server.deinit();
    try server.listen(localhost);
    try ring.register_buffers(&buffers);

    var accept_addr: os.sockaddr = undefined;
    var accept_addr_len: os.socklen_t = @sizeOf(@TypeOf(accept_addr));
    _ = try ring.accept(connInfo.accept(server.sockfd.?).cast(), server.sockfd.?, &accept_addr, &accept_addr_len, 0);
    _ = try ring.submit();

    while (ring.copy_cqe()) |cqe| {
        var info: connInfo = @bitCast(cqe.user_data);
        switch (info.type) {
            .ACCEPT => {
                print("ACCEPTED\n", .{});
                if (cqe.res >= 0) {
                    _ = try ring.read_fixed(connInfo.read(cqe.res).cast(), cqe.res, &buffers[0], 0, 0);
                }

                // Ready to accept another connection.
                _ = try ring.accept(connInfo.accept(server.sockfd.?).cast(), server.sockfd.?, &accept_addr, &accept_addr_len, 0);
            },
            .READ => {
                _ = try fmt.bufPrint(&raw_buffers[1], "HTTP/1.0 204 OK\r\n", .{});
                _ = try ring.write_fixed(connInfo.write(@intCast(info.fd)).cast(), @intCast(info.fd), &buffers[1], 0, 1);
            },
            .WRITE => {
                // After server sends the response, always close the connection.
                print("written {d}\n", .{cqe.res});
                _ = try ring.close(connInfo.close().cast(), @intCast(info.fd));
            },
            .CLOSE => {
                print("closed connection\n", .{});
            },
            else => unreachable(),
        }

        _ = try ring.submit();
    } else |err| {
        return err;
    }
}
