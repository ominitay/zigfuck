const std = @import("std");

const Self = @This();

code: std.ArrayList(u8),
loopstack: std.ArrayList(u64),
source: []const u8,

pub fn init(allocator: std.mem.Allocator, source: []const u8) !Self {
    return Self{
        .code = std.ArrayList(u8).init(allocator),
        .loopstack = std.ArrayList(u64).init(allocator),
        .source = try allocator.dupe(u8, source),
    };
}

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    self.code.deinit();
    self.loopstack.deinit();
    allocator.free(self.source);
}

pub fn gen(self: *Self) ![]const u8 {
    for (self.source) |b| {
        switch (b) {
            '>' => try self.moveRight(),
            '<' => try self.moveLeft(),
            '+' => try self.increment(),
            '-' => try self.decrement(),
            '.' => try self.output(),
            // ',' => try self.input(),
            '[' => try self.loopStart(),
            ']' => try self.loopEnd(),
            else => {}, // comment
        }
    }

    if (self.loopstack.items.len != 0) return error.NoLoopEnd;

    try self.exit();

    return self.code.toOwnedSlice();
}

pub fn moveRight(self: *Self) !void {
    // inc r10
    try self.code.appendSlice(&[_]u8{ 0x49, 0xff, 0xc2 });
}

pub fn moveLeft(self: *Self) !void {
    // dec r10
    try self.code.appendSlice(&[_]u8{ 0x49, 0xff, 0xca });
}

pub fn increment(self: *Self) !void  {
    // inc byte [r10]
    try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x02 });
}

pub fn decrement(self: *Self) !void {
    // dec byte [r10]
    try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x0a });
}

pub fn output(self: *Self) !void {
    try self.code.appendSlice(&[_]u8{
        // mov rax, 1
        0xb8, 0x01, 0x00, 0x00, 0x00,
        // mov rdi, 1
        0xbf, 0x01, 0x00, 0x00, 0x00,
        // mov rsi, r10
        0x4c, 0x89, 0xd6,
        // mov rdx, 1
        0xba, 0x01, 0x00, 0x00, 0x00,
    });
    try self.syscall();
}

// pub fn input(self: *Self) !void {

// }

pub fn loopStart(self: *Self) !void {
    try self.loopstack.append(self.code.items.len);
    try self.code.appendSlice(&[_]u8{
        // cmp byte [r10], 0
        0x41, 0x80, 0x3a, 0x00,
        // je <end of loop> ; zeroes are filled in when the loop is closed
        0x0f, 0x84, 0x00, 0x00, 0x00, 0x00,
    });
}

pub fn loopEnd(self: *Self) !void {
    const start = self.loopstack.popOrNull() orelse return error.NoLoopStart;
    const end = self.code.items.len;

    const offset = end - start;
    std.mem.copy(u8, self.code.items[start + 6 ..][0..4], &std.mem.toBytes(@intCast(i32, offset)));

    try self.code.appendSlice(&[_]u8{
        // cmp byte [r10], 0
        0x41, 0x80, 0x3a, 0x00,
        // jne <beginning of loop>
        0x0f, 0x85,
    });
    // finish our jne instruction
    try self.code.appendSlice(&std.mem.toBytes(-@intCast(i32, offset)));
}

pub fn exit(self: *Self) !void {
    try self.code.appendSlice(&[_]u8{
        // mov rax, 60
        0xb8, 0x3c, 0x00, 0x00, 0x00,
        // mov rdi, 0
        0xbf, 0x00, 0x00, 0x00, 0x00,
    });
    try self.syscall();
}

pub fn syscall(self: *Self) !void {
    // syscall
    try self.code.appendSlice(&[_]u8{ 0x0f, 0x05 });
}
