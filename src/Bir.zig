const std = @import("std");

const Self = @This();

pub const Tag = enum(u3) {
    move_right,
    move_left,
    increment,
    decrement,
    output,
    input,
    loop_begin,
    loop_end,

    pub fn isMove(t: Tag) bool {
        return switch (t) {
            .move_right, .move_left => true,
            else => false,
        };
    }

    pub fn isIncOrDec(t: Tag) bool {
        return switch (t) {
            .increment, .decrement => true,
            else => false,
        };
    }
};

pub const Instruction = packed struct {
    payload: u32 = 0,
    tag: Tag,
};

// TODO: MultiArrayList
instructions: std.ArrayList(Instruction),

pub fn optimise(self: *Self) !void {
    self.combine();
    // TODO: Implement optimisations!
}

// Combines consecutive instructions where possible
fn combine(self: *Self) void {
    var previous: *Instruction = &self.instructions.items[0];
    var i: usize = 1;
    while (i < self.instructions.items.len) {
        const current = &self.instructions.items[i];
        if ((previous.tag.isMove() and current.tag.isMove()) or (previous.tag.isIncOrDec() and current.tag.isIncOrDec())) {
            if (previous.tag == current.tag) {
                previous.payload += current.payload;
                _ = self.instructions.orderedRemove(i);
            } else {
                if (previous.payload > current.payload) {
                    previous.payload -= current.payload;
                    _ = self.instructions.orderedRemove(i);
                } else if (previous.payload < current.payload) {
                    current.payload -= previous.payload;
                    _ = self.instructions.orderedRemove(i);
                } else { // We remove both the previous and next instructions, as they cancel each other out
                    std.mem.copy(Instruction, self.instructions.items[i - 1 ..], self.instructions.items[i + 1 ..]);
                    self.instructions.items.len -= 2;
                    i -= 1;
                    if (self.instructions.items.len < 2) break;
                    if (i == 0) i = 1;
                    previous = &self.instructions.items[i - 1];
                }
            }

            continue;
        }

        previous = current;
        i += 1;
    }

    self.instructions.shrinkAndFree(self.instructions.items.len);
}
