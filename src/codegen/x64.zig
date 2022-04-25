const std = @import("std");

const Bir = @import("../Bir.zig");
const Self = @This();

code: std.ArrayList(u8),
loopstack: std.ArrayList(u64),
bir: []const Bir.Instruction,

pub fn generate(allocator: std.mem.Allocator, bir: []const Bir.Instruction) ![]const u8 {
    var self = Self{
        .code = std.ArrayList(u8).init(allocator),
        .loopstack = std.ArrayList(u64).init(allocator),
        .bir = bir,
    };
    defer self.deinit();

    return try self.gen();
}

fn deinit(self: Self) void {
    self.code.deinit();
    self.loopstack.deinit();
}

fn gen(self: *Self) ![]const u8 {
    for (self.bir) |instr| {
        switch (instr.tag) {
            .move_right => try self.moveRight(instr.payload),
            .move_left => try self.moveLeft(instr.payload),
            .increment => try self.increment(instr.payload),
            .decrement => try self.decrement(instr.payload),
            .output => try self.output(),
            .input => try self.input(),
            .loop_begin => try self.loopBegin(),
            .loop_end => try self.loopEnd(),
        }
    }

    if (self.loopstack.items.len != 0) return error.NoLoopEnd;

    try self.exit();

    return self.code.toOwnedSlice();
}

fn moveRight(self: *Self, count: u32) !void {
    std.debug.assert(count != 0);
    // we can only go up to this, since the instructions we use expect a signed operand.
    // this is probably a reasonable limitation -- is anyone going to type over 2 billion '>'s?
    std.debug.assert(count <= std.math.maxInt(i32));
    if (count == 1) {
        // inc r10
        try self.code.appendSlice(&[_]u8{ 0x49, 0xff, 0xc2 });
    } else {
        // add r10, count
        if (count <= std.math.maxInt(i8)) { // for an 8-bit add, the operand is signed
            try self.code.appendSlice(&[_]u8{ 0x49, 0x83, 0xc2, @intCast(u8, count) });
        } else {
            try self.code.appendSlice(&[_]u8{ 0x49, 0x81, 0xc2 });
            try self.code.appendSlice(&@bitCast([4]u8, count)); // write the 32 bit value
        }
    }
}

fn moveLeft(self: *Self, count: u32) !void {
    std.debug.assert(count != 0);
    std.debug.assert(count <= std.math.maxInt(i32));
    if (count == 1) {
        // dec r10
        try self.code.appendSlice(&[_]u8{ 0x49, 0xff, 0xca });
    } else {
        // sub r10, count
        if (count <= std.math.maxInt(i8)) { // for an 8-bit sub, the operand is signed
            try self.code.appendSlice(&[_]u8{ 0x49, 0x83, 0xea, @intCast(u8, count) });
        } else {
            try self.code.appendSlice(&[_]u8{ 0x49, 0x81, 0xea });
            try self.code.appendSlice(&@bitCast([4]u8, count)); // write the 32 bit value
        }
    }
}

fn increment(self: *Self, count: u32) !void {
    std.debug.assert(count != 0);
    if (count == 1) {
        // inc byte [r10]
        try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x02 });
    } else {
        // add byte [r10], count
        try self.code.appendSlice(&[_]u8{ 0x41, 0x80, 0x02, @truncate(u8, count) });
    }
}

fn decrement(self: *Self, count: u32) !void {
    std.debug.assert(count != 0);
    if (count == 1) {
        // dec byte [r10]
        try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x0a });
    } else {
        // sub byte [r10], count
        try self.code.appendSlice(&[_]u8{ 0x41, 0x80, 0x2a, @truncate(u8, count) });
    }
}

fn output(self: *Self) !void {
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

fn input(self: *Self) !void {
    try self.code.appendSlice(&[_]u8{
        // mov rax, 0
        0xb8, 0x00, 0x00, 0x00, 0x00,
        // mov rdi, 0
        0xbf, 0x00, 0x00, 0x00, 0x00,
        // mov rsi, r10
        0x4c, 0x89, 0xd6,
        // mov rdx, 1
        0xba, 0x01, 0x00, 0x00, 0x00,
    });
    try self.syscall();
}

fn loopBegin(self: *Self) !void {
    try self.loopstack.append(self.code.items.len);
    try self.code.appendSlice(&[_]u8{
        // cmp byte [r10], 0
        0x41, 0x80, 0x3a, 0x00,
        // je <end of loop> ; zeroes are filled in when the loop is closed
        0x0f, 0x84, 0x00, 0x00,
        0x00, 0x00,
    });
}

fn loopEnd(self: *Self) !void {
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
    try self.code.appendSlice(&@bitCast([4]u8, -@intCast(i32, offset)));
}

fn exit(self: *Self) !void {
    try self.code.appendSlice(&[_]u8{
        // mov rax, 60
        0xb8, 0x3c, 0x00, 0x00, 0x00,
        // mov rdi, 0
        0xbf, 0x00, 0x00, 0x00, 0x00,
    });
    try self.syscall();
}

fn syscall(self: *Self) !void {
    // syscall
    try self.code.appendSlice(&[_]u8{ 0x0f, 0x05 });
}
