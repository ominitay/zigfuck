const std = @import("std");

const Bir = @import("../Bir.zig");
const Self = @This();

code: std.ArrayList(u8),
bir: Bir.List.Slice,

pub fn generate(allocator: std.mem.Allocator, bir: Bir.List.Slice) ![]const u8 {
    var self = Self{
        .code = std.ArrayList(u8).init(allocator),
        .bir = bir,
    };
    defer self.deinit();

    return try self.gen();
}

fn deinit(self: Self) void {
    self.code.deinit();
}

fn gen(self: *Self) ![]const u8 {
    try self.genInner(0, @intCast(u32, self.bir.len));

    try self.exit();

    return self.code.toOwnedSlice();
}

fn genInner(self: *Self, index: u32, len: u32) std.mem.Allocator.Error!void {
    var i: u32 = index;
    while (i < index + len) : (i += 1) {
        const instr = self.bir.toMultiArrayList().get(i);
        switch (instr.tag) {
            .move => try self.move(instr.payload.value),
            .add => try self.add(instr.payload.value_offset.value, instr.payload.value_offset.offset),
            .output => try self.output(instr.payload.offset),
            .input => try self.input(instr.payload.offset),
            .cond_loop => {
                const start = self.code.items.len;
                try self.loopStart();
                try self.genInner(i + 1, instr.payload.cond_branch.then_len);
                i += instr.payload.cond_branch.then_len;
                try self.loopEnd(@intCast(u32, start));
            },

            .cond_branch => {
                const start = self.code.items.len;
                try self.branchStart();
                try self.genInner(i + 1, instr.payload.cond_branch.then_len);
                i += instr.payload.cond_branch.then_len;
                self.branchEnd(@intCast(u32, start));
            },
            .set => try self.set(instr.payload.value_offset.value, instr.payload.value_offset.offset),
            .mul => try self.mul(instr.payload.value_offset.value, instr.payload.value_offset.offset),
        }
    }
}

fn move(self: *Self, value: i32) !void {
    std.debug.assert(value != 0);
    if (value > 0) {
        if (value == 1) {
            // inc r10
            try self.code.appendSlice(&[_]u8{ 0x49, 0xff, 0xc2 });
        } else {
            // add r10, value
            if (value <= std.math.maxInt(i8)) {
                try self.code.appendSlice(&[_]u8{ 0x49, 0x83, 0xc2, @intCast(u8, value) });
            } else {
                try self.code.appendSlice(&[_]u8{ 0x49, 0x81, 0xc2 });
                try self.code.appendSlice(&@bitCast([4]u8, value)); // write the 32 bit value
            }
        }
    } else {
        if (-value == 1) {
            // dec r10
            try self.code.appendSlice(&[_]u8{ 0x49, 0xff, 0xca });
        } else {
            // sub r10, value
            if (-value <= std.math.maxInt(i8)) {
                try self.code.appendSlice(&[_]u8{ 0x49, 0x83, 0xea, @intCast(u8, -value) });
            } else {
                try self.code.appendSlice(&[_]u8{ 0x49, 0x81, 0xea });
                try self.code.appendSlice(&@bitCast([4]u8, -value)); // write the 32 bit value
            }
        }
    }
}

fn add(self: *Self, value: i32, offset: i32) !void {
    std.debug.assert(value != 0);
    if (value > 0) {
        if (offset == 0) {
            if (value == 1) {
                // inc byte [r10]
                try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x02 });
            } else {
                // add byte [r10], value
                try self.code.appendSlice(&[_]u8{ 0x41, 0x80, 0x02, @intCast(u8, value) });
            }
        } else if (offset <= std.math.maxInt(i8) and offset >= std.math.maxInt(i8)) {
            if (value == 1) {
                // inc byte [r10 + offset]
                try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x42, @bitCast(u8, @intCast(i8, offset)) });
            } else {
                // add byte [r10 + offset], value
                try self.code.appendSlice(&[_]u8{ 0x41, 0x80, 0x42, @bitCast(u8, @intCast(i8, offset)), @intCast(u8, value) });
            }
        } else {
            if (value == 1) {
                // inc byte [r10 + offset]
                try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x82 });
                try self.code.appendSlice(&@bitCast([4]u8, offset)); // write the 32 bit displacement
            } else {
                // add byte [r10 + offset], value
                try self.code.appendSlice(&[_]u8{ 0x41, 0x80, 0x82 });
                try self.code.appendSlice(&@bitCast([4]u8, offset)); // write the 32 bit displacement
                try self.code.append(@intCast(u8, value)); // write the 8 bit value
            }
        }
    } else {
        if (offset == 0) {
            if (-value == 1) {
                // dec byte [r10]
                try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x0a });
            } else {
                // sub byte [r10], value
                try self.code.appendSlice(&[_]u8{ 0x41, 0x80, 0x2a, @intCast(u8, -value) });
            }
        } else if (offset <= std.math.maxInt(i8) and offset >= std.math.maxInt(i8)) {
            if (-value == 1) {
                // inc byte [r10 + offset]
                try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x4a, @bitCast(u8, @intCast(i8, offset)) });
            } else {
                // sub byte [r10 + offset], value
                try self.code.appendSlice(&[_]u8{ 0x41, 0x80, 0x6a, @bitCast(u8, @intCast(i8, offset)), @intCast(u8, -value) });
            }
        } else {
            if (-value == 1) {
                // inc byte [r10 + offset]
                try self.code.appendSlice(&[_]u8{ 0x41, 0xfe, 0x8a });
                try self.code.appendSlice(&@bitCast([4]u8, offset)); // write the 32 bit displacement
            } else {
                // sub byte [r10 + offset], value
                try self.code.appendSlice(&[_]u8{ 0x41, 0x80, 0xaa });
                try self.code.appendSlice(&@bitCast([4]u8, offset)); // write the 32 bit displacement
                try self.code.append(@intCast(u8, -value)); // write the 8 bit value
            }
        }
    }
}

fn output(self: *Self, offset: i32) !void {
    std.debug.assert(offset == 0);
    try self.code.appendSlice(&[_]u8{
        // mov rax, 1
        0xb8, 0x01, 0x00, 0x00, 0x00,
        // mov rdi, 1
        0xbf, 0x01, 0x00, 0x00, 0x00,
        // mov rsi, r10
        0x4c, 0x89, 0xd6,
        // mov rdx, 1
        0xba, 0x01,
        0x00, 0x00, 0x00,
    });
    try self.syscall();
}

fn input(self: *Self, offset: i32) !void {
    std.debug.assert(offset == 0);
    try self.code.appendSlice(&[_]u8{
        // mov rax, 0
        0xb8, 0x00, 0x00, 0x00, 0x00,
        // mov rdi, 0
        0xbf, 0x00, 0x00, 0x00, 0x00,
        // mov rsi, r10
        0x4c, 0x89, 0xd6,
        // mov rdx, 1
        0xba, 0x01,
        0x00, 0x00, 0x00,
    });
    try self.syscall();
}

fn loopStart(self: *Self) !void {
    try self.code.appendSlice(&[_]u8{
        // cmp byte [r10], 0
        0x41, 0x80, 0x3a, 0x00,
        // je <end of loop> ; zeroes are filled in when the loop is closed
        0x0f, 0x84, 0x00, 0x00,
        0x00, 0x00,
    });
}

fn loopEnd(self: *Self, start: u32) !void {
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

fn branchStart(self: *Self) !void {
    try self.code.appendSlice(&[_]u8{
        // cmp byte [r10], 0
        0x41, 0x80, 0x3a, 0x00,
        // je <end of branch> ; zeroes are filled in when the branch is closed
        0x0f, 0x84, 0x00, 0x00, 0x00, 0x00,
    });
}

fn branchEnd(self: *Self, start: u32) void {
    const end = self.code.items.len;
    const offset = end - start - 10;
    std.mem.copy(u8, self.code.items[start + 6 ..][0..4], &@bitCast([4]u8, @intCast(i32, offset)));
}

fn set(self: *Self, value: i32, offset: i32) !void {
    if (offset == 0) {
        // mov [r10], value
        try self.code.appendSlice(&[_]u8{ 0x41, 0xc6, 0x02, @intCast(u8, value) });
    } else if (offset <= std.math.maxInt(i8) and offset >= std.math.minInt(i8)) {
        // mov [r10 + offset], value
        try self.code.appendSlice(&[_]u8{ 0x41, 0xc6, 0x42, @bitCast(u8, @intCast(i8, offset)), @intCast(u8, value) });
    } else {
        // mov [r10 + offset], value
        try self.code.appendSlice(&[_]u8{ 0x41, 0xc6, 0x82 });
        try self.code.appendSlice(&@bitCast([4]u8, offset));
        try self.code.append(@intCast(u8, value));
    }
}

fn mul(self: *Self, value: i32, offset: i32) !void {
    try self.code.appendSlice(&[_]u8{
        // mov al, value
        0xb0, @intCast(u8, std.math.absInt(value) catch unreachable),
        // mul [r10]
        0x41, 0xf6,
        0x22,
    });
    if (value > 0) {
        if (offset == 0) {
            try self.code.appendSlice(&[_]u8{
                // add [r10], al
                0x41, 0x00, 0x02,
            });
        } else if (offset <= std.math.maxInt(i8) and offset >= std.math.minInt(i8)) {
            try self.code.appendSlice(&[_]u8{
                // add [r10 + offset], al
                0x41, 0x00, 0x42, @bitCast(u8, @intCast(i8, offset)),
            });
        } else {
            // add [r10 + offset], al
            try self.code.appendSlice(&[_]u8{ 0x41, 0x00, 0x82 });
            try self.code.appendSlice(&@bitCast([4]u8, offset));
        }
    } else {
        if (offset == 0) {
            try self.code.appendSlice(&[_]u8{
                // sub [r10], al
                0x41, 0x28, 0x02,
            });
        } else if (offset <= std.math.maxInt(i8) and offset >= std.math.minInt(i8)) {
            try self.code.appendSlice(&[_]u8{
                // sub [r10 + offset], al
                0x41, 0x28, 0x42, @bitCast(u8, @intCast(i8, offset)),
            });
        } else {
            // sub [r10 + offset], al
            try self.code.appendSlice(&[_]u8{ 0x41, 0x28, 0x82 });
            try self.code.appendSlice(&@bitCast([4]u8, offset));
        }
    }
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
