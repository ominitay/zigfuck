const std = @import("std");
const Bir = @import("Bir.zig");

const State = enum {
    start,
    move,
    add,
};

const ParseError = error{ ExpectedBlockEnd, UnexpectedBlockEnd } || std.mem.Allocator.Error;

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!Bir {
    var instructions = std.MultiArrayList(Bir.Instruction){};
    errdefer instructions.deinit(allocator);
    try instructions.ensureTotalCapacity(allocator, source.len / 2); // Probably a reasonable amount to reserve, should be changed after testing

    _ = try parseInner(allocator, source, &instructions);

    instructions.shrinkAndFree(allocator, instructions.len);

    return Bir.init(allocator, instructions);
}

// We recursively call this function on blocks. The number of instructions generated is returned.
fn parseInner(allocator: std.mem.Allocator, source: []const u8, instructions: *Bir.List) ParseError!u32 {
    const initial_len = instructions.len;

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
                '.' => try instructions.append(allocator, .{ .tag = .output, .payload = .{ .offset = 0 } }),
                ',' => try instructions.append(allocator, .{ .tag = .input, .payload = .{ .offset = 0 } }),
                '[' => {
                    const block_start = i + 1;
                    const block_end = end: {
                        var j: u32 = block_start;
                        var depth: u32 = 0;

                        while (j < source.len) : (j += 1) {
                            switch (source[j]) {
                                ']' => {
                                    if (depth == 0) break :end j;
                                    depth -= 1;
                                },
                                '[' => depth += 1,
                                else => {},
                            }
                        }

                        return ParseError.ExpectedBlockEnd;
                    };

                    i = block_end;

                    const instr_i = instructions.len;
                    try instructions.append(allocator, .{ .tag = .cond_loop, .payload = undefined });

                    const block_len = try parseInner(allocator, source[block_start..block_end], instructions);

                    instructions.items(.payload)[instr_i] = .{ .cond_branch = .{ .then_len = block_len } };
                },
                // A block end instruction should never be reached here in valid brainfuck, so we return an error.
                ']' => return ParseError.UnexpectedBlockEnd,
                else => {},
            },
            .move => switch (source[i]) {
                '>' => counter += 1,
                '<' => counter -= 1,
                ' ', '\n' => {},
                else => {
                    state = .start;
                    if (counter != 0) try instructions.append(allocator, .{ .tag = .move, .payload = .{ .value = counter } });
                    continue;
                },
            },
            .add => switch (source[i]) {
                '+' => counter += 1,
                '-' => counter -= 1,
                ' ', '\n' => {},
                else => {
                    state = .start;
                    if (counter != 0) try instructions.append(allocator, .{ .tag = .add, .payload = .{ .value_offset = .{ .value = counter, .offset = 0 } } });
                    continue;
                },
            },
        }

        i += 1;
    }

    switch (state) {
        .start => {},
        .move => if (counter != 0) try instructions.append(allocator, .{ .tag = .move, .payload = .{ .value = counter } }),
        .add => if (counter != 0) try instructions.append(allocator, .{ .tag = .add, .payload = .{ .value_offset = .{ .value = counter, .offset = 0 } } }),
    }

    return @intCast(u32, instructions.len - initial_len);
}
