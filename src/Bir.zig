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
    // TODO: Implement optimisations!
}
