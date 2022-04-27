const std = @import("std");

const Self = @This();

pub const Tag = enum(u3) {
    add, // Payload.value_offset
    move, // Payload.value
    output, // Payload.value
    input, // Payload.value
    loop_begin, // Payload.none
    loop_end, // Payload.none

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
    payload: Payload,
    tag: Tag,
};

pub const Payload = packed union {
    value_offset: packed struct {
        value: i32,
        offset: i32,
    },

    value: i32,
    none: void,
};

pub const List = std.MultiArrayList(Instruction);

instructions: List,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, instructions: List) Self {
    return Self{
        .instructions = instructions,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.instructions.deinit(self.allocator);
}

pub fn optimise(self: *Self) !void {
    defer self.instructions.shrinkAndFree(self.allocator, self.instructions.len);
    try self.sortByOffset();
    // TODO: Implement optimisations!
}

/// This optimisation pass attempts to sort additions and subtractions by offset, allowing us to use just one pointer increment at the end.
/// TODO: Handle I/O, and simple loops in this optimisation.
fn sortByOffset(self: *Self) !void {
    var generated = List{};
    errdefer generated.deinit(self.allocator);
    try generated.ensureTotalCapacity(self.allocator, self.instructions.len);

    var changes = std.AutoHashMap(i32, i32).init(self.allocator); // add { offset, value }
    defer changes.deinit();
    var offset: i32 = 0;

    var i: u32 = 0;
    while (i < self.instructions.len) : (i += 1) {
        switch (self.instructions.items(.tag)[i]) {
            .add => {
                const instr_value = self.instructions.get(i).payload.value_offset;
                const entry = try changes.getOrPutValue(offset + instr_value.offset, 0);
                entry.value_ptr.* += instr_value.value;
            },
            .move => {
                const instr_value = self.instructions.get(i).payload.value;
                offset += instr_value;
            },
            else => {
                const change_post_offset = changes.fetchRemove(offset);
                if (changes.count() != 0) {
                    var iter = changes.iterator();
                    while (iter.next()) |change| {
                        generated.appendAssumeCapacity(.{ .tag = .add, .payload = .{ .value_offset = .{
                            .value = change.value_ptr.*,
                            .offset = change.key_ptr.*,
                        }}});
                    }
                    changes.clearRetainingCapacity();
                }

                if (offset != 0) {
                    generated.appendAssumeCapacity(.{ .tag = .move, .payload = .{ .value = offset }});
                    offset = 0;
                }

                if (change_post_offset) |change|
                    generated.appendAssumeCapacity(.{ .tag = .add, .payload = .{ .value_offset = .{ .value = change.value, .offset = 0 }}});

                generated.appendAssumeCapacity(self.instructions.get(i));
            },
        }
    }

    self.instructions.deinit(self.allocator);
    self.instructions = generated;
}
