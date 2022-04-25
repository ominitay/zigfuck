const std = @import("std");
const Bir = @import("Bir.zig");

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Bir {
    var instructions = std.ArrayList(Bir.Instruction).init(allocator);

    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        switch (source[i]) {
            '>' => try instructions.append(.{ .tag = .move_right, .payload = 1 }),
            '<' => try instructions.append(.{ .tag = .move_left, .payload = 1 }),
            '+' => try instructions.append(.{ .tag = .increment, .payload = 1 }),
            '-' => try instructions.append(.{ .tag = .decrement, .payload = 1 }),
            '.' => try instructions.append(.{ .tag = .output}),
            ',' => try instructions.append(.{ .tag = .input}),
            '[' => try instructions.append(.{ .tag = .loop_begin}),
            ']' => try instructions.append(.{ .tag = .loop_end}),
            else => {},
        }
    }

    return Bir{
        .instructions = instructions,
    };
}
