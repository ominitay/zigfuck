const std = @import("std");
const Bir = @import("Bir.zig");

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Bir {
    var instructions = std.MultiArrayList(Bir.Instruction){};
    try instructions.ensureTotalCapacity(allocator, source.len);

    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        switch (source[i]) {
            '>' => try instructions.append(allocator, .{ .tag = .move_right, .payload = 1 }),
            '<' => try instructions.append(allocator, .{ .tag = .move_left, .payload = 1 }),
            '+' => try instructions.append(allocator, .{ .tag = .increment, .payload = 1 }),
            '-' => try instructions.append(allocator, .{ .tag = .decrement, .payload = 1 }),
            '.' => try instructions.append(allocator, .{ .tag = .output }),
            ',' => try instructions.append(allocator, .{ .tag = .input }),
            '[' => try instructions.append(allocator, .{ .tag = .loop_begin }),
            ']' => try instructions.append(allocator, .{ .tag = .loop_end }),
            else => {},
        }
    }

    instructions.shrinkAndFree(allocator, instructions.len);

    return Bir{
        .instructions = instructions,
        .allocator = allocator,
    };
}
