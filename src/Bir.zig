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

pub const Instruction = struct {
    payload: u32 = 0,
    tag: Tag,
};

pub const List = std.MultiArrayList(Instruction);

instructions: List,
allocator: std.mem.Allocator,

pub fn optimise(self: *Self) !void {
    defer self.instructions.shrinkAndFree(self.allocator, self.instructions.len);
    self.combine();
    // TODO: Implement optimisations!
}

// Combines consecutive instructions where possible
fn combine(self: *Self) void {
    var previous_index: usize = 0;
    var i: usize = 1;
    while (i < self.instructions.len) {
        var previous = self.instructions.get(previous_index);
        var current = self.instructions.get(i);
        if ((previous.tag.isMove() and current.tag.isMove()) or (previous.tag.isIncOrDec() and current.tag.isIncOrDec())) {
            if (previous.tag == current.tag) {
                previous.payload += current.payload;
                self.instructions.set(previous_index, previous);
                _ = self.instructions.orderedRemove(i);
            } else {
                if (previous.payload > current.payload) {
                    previous.payload -= current.payload;
                    self.instructions.set(previous_index, previous);
                    _ = self.instructions.orderedRemove(i);
                } else if (previous.payload < current.payload) {
                    current.payload -= previous.payload;
                    self.instructions.set(previous_index, current);
                    _ = self.instructions.orderedRemove(i);
                } else { // We remove both the previous and next instructions, as they cancel each other out
                    _ = self.instructions.orderedRemove(i);
                    _ = self.instructions.orderedRemove(previous_index);
                    i -= 1;
                    if (self.instructions.len < 2) break;
                    if (i == 0) i = 1;
                    previous_index = i - 1;
                }
            }

            continue;
        }

        previous_index = i;
        i += 1;
    }
}
