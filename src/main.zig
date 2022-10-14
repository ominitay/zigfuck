const std = @import("std");
const parse = @import("parse.zig").parse;
const codegen = @import("codegen.zig");
const elf = @import("elf.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // own path
    const source_path = args.next().?;
    const out_path = args.next().?;
    std.debug.assert(args.skip() == false);

    const output_dir = std.fs.cwd();

    var source_file = try std.fs.cwd().openFile(source_path, .{});
    defer source_file.close();

    const source_bytes = try source_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source_bytes);

    var bir = try parse(allocator, source_bytes);
    defer bir.deinit();

    try bir.optimise();

    try codegen.x64.generate(allocator, output_dir, out_path, bir.slice());
}
