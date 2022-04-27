const std = @import("std");
const Bir = @import("Bir.zig");

const State = enum {
    start,
    right,
    left,
    inc,
    dec,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Bir {
    var instructions = std.MultiArrayList(Bir.Instruction){};
    errdefer instructions.deinit(allocator);
    try instructions.ensureTotalCapacity(allocator, source.len / 2); // Probably a reasonable amount to reserve, should be changed after testing

    var state: State = .start;
    var counter: u32 = 0;

    var i: usize = 0;
    while (i < source.len) {
        switch (state) {
            .start => switch (source[i]) {
                '>' => {
                    state = .right;
                    counter = 1;
                },
                '<' => {
                    state = .left;
                    counter = 1;
                },
                '+' => {
                    state = .inc;
                    counter = 1;
                },
                '-' => {
                    state = .dec;
                    counter = 1;
                },
                '.' => try instructions.append(allocator, .{ .tag = .output }),
                ',' => try instructions.append(allocator, .{ .tag = .input }),
                '[' => try instructions.append(allocator, .{ .tag = .loop_begin }),
                ']' => try instructions.append(allocator, .{ .tag = .loop_end }),
                else => {},
            },
            .right => switch (source[i]) {
                '>' => counter += 1,
                ' ', '\n' => {},
                else => {
                    state = .start;
                    try instructions.append(allocator, .{ .tag = .move_right, .payload = counter });
                    continue;
                },
            },
            .left => switch (source[i]) {
                '<' => counter += 1,
                ' ', '\n' => {},
                else => {
                    state = .start;
                    try instructions.append(allocator, .{ .tag = .move_left, .payload = counter });
                    continue;
                },
            },
            .inc => switch (source[i]) {
                '+' => counter += 1,
                ' ', '\n' => {},
                else => {
                    state = .start;
                    try instructions.append(allocator, .{ .tag = .increment, .payload = counter });
                    continue;
                },
            },
            .dec => switch (source[i]) {
                '-' => counter += 1,
                ' ', '\n' => {},
                else => {
                    state = .start;
                    try instructions.append(allocator, .{ .tag = .decrement, .payload = counter });
                    continue;
                },
            },
        }

        i += 1;
    }

    instructions.shrinkAndFree(allocator, instructions.len);

    return Bir{
        .instructions = instructions,
        .allocator = allocator,
    };
}
