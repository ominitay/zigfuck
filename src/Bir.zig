const std = @import("std");

const Self = @This();

pub const Tag = enum(u3) {
    // Adds a signed value to the cell specified by the offset to the current cell.
    // Uses the `value_offset` field.
    add,
    // Adds a signed value to the current cell pointer.
    // Uses the `value` field.
    move,
    // Outputs the value in the cell specified by the offset to stdout.
    // Uses the `offset` field.
    output,
    // Reads a character from stdin, setting the cell specified by the offset to the value.
    // If EOF is reached, the value in the cell will be left unchanged.
    // Uses the `offset` field.`
    input,
    // Loops over the specified instructions, so long as the current cell is not zero.
    // Uses the `cond_branch` field.
    cond_loop,

    // Optimisations

    // Conditionally skips a block of code. This is generated in optimising multiplication loops.
    // Uses the `cond_branch` field.
    cond_branch,
    // Multiplies the value by the current cell, and adds it to the cell specified by the offset.
    // Uses the `value_offset` field.
    mul,
    // Sets the cell specified by the offset to the specified value.
    // Uses the `value_offset` field.
    set,

    pub fn isBlock(t: Tag) bool {
        return switch (t) {
            .cond_loop, .cond_branch => true,
            .add, .move, .output, .input, .mul, .set => false,
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
    offset: i32,
    cond_branch: packed struct {
        // This field specifies the length of the branch's 'then' block.
        then_len: u32,
    },
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

pub fn slice(self: Self) List.Slice {
    return self.instructions.slice();
}

pub fn print(self: Self, writer: anytype) !void {
    try writer.print("Bir Dump:\nInstruction count: {d}\n", .{self.instructions.len});
    try self.printInner(writer, 0, @intCast(u32, self.instructions.len), 0);
}

fn printInner(self: Self, writer: anytype, index: u32, len: u32, indent: u32) @TypeOf(writer).Error!void {
    var i: u32 = index;
    while (i < index + len) : (i += 1) {
        const instr = self.instructions.get(i);
        try writer.writeByteNTimes(' ', indent);
        try writer.print("%{d}: {s}", .{ i, @tagName(instr.tag) });
        switch (instr.tag) {
            .add, .mul, .set => try writer.print(", {d} @ {d}", .{ instr.payload.value_offset.value, instr.payload.value_offset.offset }),
            .move => try writer.print(", {d}", .{instr.payload.value}),
            .output, .input => try writer.print(", {d}", .{instr.payload.offset}),
            .cond_loop, .cond_branch => {
                try writer.writeAll(", {\n");
                try self.printInner(writer, i + 1, instr.payload.cond_branch.then_len, indent + 2);
                i += instr.payload.cond_branch.then_len;
                try writer.writeByteNTimes(' ', indent);
                try writer.writeAll("}");
            },
        }
        try writer.writeByte('\n');
    }
}

pub fn optimise(self: *Self) !void {
    defer self.instructions.shrinkAndFree(self.allocator, self.instructions.len);
    try self.sortByOffset();
    try self.simpleLoop();
    // TODO: Implement optimisations!
}

/// This optimisation pass attempts to sort additions and subtractions by offset, allowing us to use just one pointer increment at the end.
/// TODO: Handle I/O, and simple loops in this optimisation.
fn sortByOffset(self: *Self) !void {
    var generated = List{};
    errdefer generated.deinit(self.allocator);
    try generated.ensureTotalCapacity(self.allocator, self.instructions.len);

    _ = try self.sortByOffsetInner(0, @intCast(u32, self.instructions.len), &generated);

    self.instructions.deinit(self.allocator);
    self.instructions = generated;
}

fn sortByOffsetInner(self: *Self, index: u32, len: u32, generated: *List) std.mem.Allocator.Error!u32 {
    const initial_len = generated.len;

    var changes = std.AutoHashMap(i32, i32).init(self.allocator); // add { offset, value }
    defer changes.deinit();
    var offset: i32 = 0;

    var i: u32 = index;
    while (i < index + len) : (i += 1) {
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
            else => |tag| {
                const change_post_offset = changes.fetchRemove(offset);
                if (changes.count() != 0) {
                    var iter = changes.iterator();
                    while (iter.next()) |change| {
                        generated.appendAssumeCapacity(.{ .tag = .add, .payload = .{ .value_offset = .{
                            .value = change.value_ptr.*,
                            .offset = change.key_ptr.*,
                        } } });
                    }
                    changes.clearRetainingCapacity();
                }

                if (offset != 0) {
                    generated.appendAssumeCapacity(.{ .tag = .move, .payload = .{ .value = offset } });
                    offset = 0;
                }

                if (change_post_offset) |change|
                    generated.appendAssumeCapacity(.{ .tag = .add, .payload = .{ .value_offset = .{ .value = change.value, .offset = 0 } } });

                if (tag.isBlock()) {
                    const instr_i = generated.len;
                    generated.appendAssumeCapacity(.{ .tag = tag, .payload = undefined });

                    const old_len = self.instructions.items(.payload)[i].cond_branch.then_len;
                    const new_len = try self.sortByOffsetInner(i + 1, old_len, generated);
                    i += old_len;

                    generated.items(.payload)[instr_i] = .{ .cond_branch = .{ .then_len = new_len } };
                } else {
                    generated.appendAssumeCapacity(self.instructions.get(i));
                }
            },
        }
    }

    const change_post_offset = changes.fetchRemove(offset);
    if (changes.count() != 0) {
        var iter = changes.iterator();
        while (iter.next()) |change| {
            generated.appendAssumeCapacity(.{ .tag = .add, .payload = .{ .value_offset = .{
                .value = change.value_ptr.*,
                .offset = change.key_ptr.*,
            } } });
        }
        changes.clearRetainingCapacity();
    }

    if (offset != 0) {
        generated.appendAssumeCapacity(.{ .tag = .move, .payload = .{ .value = offset } });
        offset = 0;
    }

    if (change_post_offset) |change|
        generated.appendAssumeCapacity(.{ .tag = .add, .payload = .{ .value_offset = .{ .value = change.value, .offset = 0 } } });

    return @intCast(u32, generated.len - initial_len);
}

fn simpleLoop(self: *Self) !void {
    var generated = List{};
    errdefer generated.deinit(self.allocator);
    try generated.ensureTotalCapacity(self.allocator, self.instructions.len);

    try self.simpleLoopInner(0, @intCast(u32, self.instructions.len), false, &generated);

    self.instructions.deinit(self.allocator);
    self.instructions = generated;
}

fn simpleLoopInner(self: *Self, index: u32, len: u32, is_block: bool, generated: *List) std.mem.Allocator.Error!void {
    var is_simple = false;
    var i = index;

    var changes = std.AutoHashMap(i32, i32).init(self.allocator);
    defer changes.deinit(); // add { offset, value }

    if (is_block and self.instructions.items(.tag)[index - 1] == .cond_loop) {
        is_simple = blk: while (i < index + len) {
            switch (self.instructions.items(.tag)[i]) {
                .add => {
                    const value_offset = self.instructions.items(.payload)[i].value_offset;
                    const entry = try changes.getOrPutValue(value_offset.offset, 0);
                    entry.value_ptr.* += value_offset.value;
                },
                else => break :blk false,
            }
            i += 1;
        } else if (changes.fetchRemove(0)) |first| first.value == -1 else false;
    }

    if (is_simple) {
        if (changes.count() != 0) {
            generated.appendAssumeCapacity(.{ .tag = .cond_branch, .payload = undefined });
            const initial_len = generated.len;

            var iter = changes.iterator();
            while (iter.next()) |change|
                generated.appendAssumeCapacity(.{ .tag = .mul, .payload = .{ .value_offset = .{ .value = change.value_ptr.*, .offset = change.key_ptr.* } } });

            generated.appendAssumeCapacity(.{ .tag = .set, .payload = .{ .value_offset = .{ .value = 0, .offset = 0 } } });

            generated.items(.payload)[initial_len - 1] = .{ .cond_branch = .{ .then_len = @intCast(u32, generated.len - initial_len) } };
        } else {
            generated.appendAssumeCapacity(.{ .tag = .set, .payload = .{ .value_offset = .{ .value = 0, .offset = 0 } } });
        }
    } else {
        if (is_block) generated.appendAssumeCapacity(.{ .tag = self.instructions.items(.tag)[index - 1], .payload = undefined });
        const initial_len = generated.len;
        i = index;
        while (i < index + len) : (i += 1) {
            const tag = self.instructions.items(.tag)[i];
            if (tag.isBlock()) {
                const block_len = self.instructions.items(.payload)[i].cond_branch.then_len;
                try self.simpleLoopInner(i + 1, block_len, true, generated);
                i += block_len;
            }
            else {
                generated.appendAssumeCapacity(self.instructions.get(i));
            }
        }
        if (is_block) generated.items(.payload)[initial_len - 1] = .{ .cond_branch = .{ .then_len = @intCast(u32, generated.len - initial_len) } };
    }
}
