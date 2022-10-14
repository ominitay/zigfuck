const std = @import("std");
const args = @import("args");

const parse = @import("parse.zig").parse;
const codegen = @import("codegen.zig");
const elf = @import("elf.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = try args.parseForCurrentProcess(struct {
        output: ?[]const u8 = null,
        @"verbose-bir": bool = false,

        pub const shorthands = .{
            .o = "output",
        };
    }, allocator, .print);
    defer options.deinit();

    const source_path = options.positionals[0];
    const out_path = options.options.output;
    const output_dir = std.fs.cwd();

    var source_file = try std.fs.cwd().openFile(source_path, .{});
    defer source_file.close();

    const source_bytes = try source_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source_bytes);

    var bir = try parse(allocator, source_bytes);
    defer bir.deinit();

    if (options.options.@"verbose-bir") try bir.print(stdout);

    try bir.optimise();


    if (options.options.@"verbose-bir") {
        try stdout.writeAll("Post-optimisation:\n");
        try bir.print(stdout);
    }

    try codegen.x64.generate(allocator, output_dir, out_path, bir.slice());
}
