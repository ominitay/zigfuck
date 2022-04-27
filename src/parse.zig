const std = @import("std");
const Bir = @import("Bir.zig");

const State = enum {
    start,
    move,
    add,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Bir {
    var instructions = std.MultiArrayList(Bir.Instruction){};
    errdefer instructions.deinit(allocator);
    try instructions.ensureTotalCapacity(allocator, source.len / 2); // Probably a reasonable amount to reserve, should be changed after testing

    var state: State = .start;
    var counter: i32 = 0;

    var i: u32 = 0;
    while (i < source.len) {
        switch (state) {
            .start => switch (source[i]) {
                '>' => {
                    state = .move;
                    counter = 1;
                },
                '<' => {
                    state = .move;
                    counter = -1;
                },
                '+' => {
                    state = .add;
                    counter = 1;
                },
                '-' => {
                    state = .add;
                    counter = -1;
                },
                '.' => try instructions.append(allocator, .{ .tag = .output, .payload = .{ .value = 0 }}),
                ',' => try instructions.append(allocator, .{ .tag = .input, .payload = .{ .value = 0 }}),
                '[' => try instructions.append(allocator, .{ .tag = .loop_begin, .payload = .{ .none = {} }}),
                ']' => try instructions.append(allocator, .{ .tag = .loop_end, .payload = .{ .none = {} }}),
                else => {},
            },
            .move => switch (source[i]) {
                '>' => counter += 1,
                '<' => counter -= 1,
                ' ', '\n' => {},
                else => {
                    state = .start;
                    if (counter != 0) try instructions.append(allocator, .{ .tag = .move, .payload = .{ .value = counter }});
                    continue;
                },
            },
            .add => switch (source[i]) {
                '+' => counter += 1,
                '-' => counter -= 1,
                ' ', '\n' => {},
                else => {
                    state = .start;
                    if (counter != 0) try instructions.append(allocator, .{ .tag = .add, .payload = .{ .value_offset = .{ .value = counter, .offset = 0 }}});
                    continue;
                },
            },
        }

        i += 1;
    }

    instructions.shrinkAndFree(allocator, instructions.len);

    return Bir.init(allocator, instructions);
}
