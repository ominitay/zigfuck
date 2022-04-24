const std = @import("std");
const parse = @import("parse.zig").parse;
const codegen = @import("codegen.zig");
const elf = @import("elf.zig");

const cell_count = 30000;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // own path
    const source_path = args.next().?;
    // const out_path = args.next().?;
    // std.debug.assert(args.skip() == false);

    var source_file = try std.fs.cwd().openFile(source_path, .{});
    defer source_file.close();

    const source_bytes = try source_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source_bytes);

    var bir = try parse(allocator, source_bytes);
    std.debug.print("{any}\n", .{bir.instructions.items});
    try bir.optimise();
    std.debug.print("{any}\n", .{bir.instructions.items});

    // var out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true, .mode = 0o775 });
    // defer out_file.close();
    // const out_writer = out_file.writer();

    // try generate(allocator, codegen.x64, source_bytes, out_writer);
}

fn generate(allocator: std.mem.Allocator, Codegen: anytype, source: []const u8, writer: anytype) !void {
    var buf = std.io.bufferedWriter(writer);
    const w = buf.writer();

    var cg = try Codegen.init(allocator, source);
    defer cg.deinit(allocator);
    const code = try cg.gen();
    defer allocator.free(code);
    // const code = [_]u8{ 0xb8, 0xe7, 0x00, 0x00, 0x00, 0x48, 0x8b, 0x3c, 0x25, 0x91, 0x00, 0x40, 0x00, 0x0f, 0x05, 0x2a };
    const code_prefix = [_]u8{ 0x49, 0xba } ++ [_]u8{ 0x00 } ** 8; // this is used to load the address of the first cell to r10. the address is copied in later once we know what it will be.
    const shstrtab = "\x00.text\x00.bss\x00.shstrtab\x00".*;
    const section_count = 4;

    const bss_len = cell_count;

    const sections = try std.mem.concat(allocator, u8, &[_][]const u8{ &code_prefix, code, &shstrtab });
    defer allocator.free(sections);

    const header_len = @sizeOf(elf.Header) + @sizeOf(elf.ProgramHeader);

    const text_pos = header_len;
    const shstrtab_pos = text_pos + code.len + code_prefix.len;
    const bss_pos = shstrtab_pos + shstrtab.len;
    const section_header_pos = header_len + sections.len;
    const file_size = header_len + sections.len + section_count * @sizeOf(elf.SectionHeader);

    std.mem.copy(u8, sections[2..], @bitCast([8]u8, bss_pos + elf.base_addr)[0..]); // add the correct address for the first cell

    const header = elf.Header{
        .class = .@"64",
        .endian = .little,
        .type = .executable,
        .arch = .x64,
        .entry = text_pos + elf.base_addr,
        .shdr_off = section_header_pos,
        .phdr_ent_count = 1,
        .shdr_ent_count = section_count,
        .shdr_str_index = 2,
    };
    try w.writeStruct(header);

    const program_header = elf.ProgramHeader{
        .type = .loadable,
        .flags = .{ .executable = true, .writable = true, .readable = true },
        .offset = 0,
        .virt_addr = elf.base_addr,
        .phys_addr = elf.base_addr,
        .file_size = file_size,
        .mem_size = file_size,
        .alignment = 0x1000,
    };
    try w.writeStruct(program_header);

    try w.writeAll(sections[0..]);

    const text_off = @intCast(u32, std.mem.indexOf(u8, &shstrtab, ".text").?);
    const bss_off = @intCast(u32, std.mem.indexOf(u8, &shstrtab, ".bss").?);
    const shstrtab_off = @intCast(u32, std.mem.indexOf(u8, &shstrtab, ".shstrtab").?);
    const section_headers = [section_count]elf.SectionHeader{
        .{ // STN_UNDEF
            .name = 0,
            .type = .@"null",
            .flags = .{},
            .addr = 0,
            .offset = 0,
            .size = 0,
            .link = 0,
            .info = 0,
            .alignment = 0,
            .entry_size = 0,
        },
        .{ // .text
            .name = text_off,
            .type = .prog_bits,
            .flags = .{ .alloc = true, .executable = true },
            .addr = text_pos + elf.base_addr,
            .offset = text_pos,
            .size = code.len + code_prefix.len,
            .link = 0,
            .info = 0,
            .alignment = 0,
            .entry_size = 0,
        },
        .{ // .shstrtab
            .name = shstrtab_off,
            .type = .string_table,
            .flags = .{},
            .addr = shstrtab_pos + elf.base_addr,
            .offset = shstrtab_pos,
            .size = shstrtab.len,
            .link = 0,
            .info = 0,
            .alignment = 0,
            .entry_size = 0,
        },
        .{ // .bss
            .name = bss_off,
            .type = .no_bits,
            .flags = .{ .writable = true, .alloc = true },
            .addr = bss_pos + elf.base_addr,
            .offset = bss_pos,
            .size = bss_len,
            .link = 0,
            .info = 0,
            .alignment = 0,
            .entry_size = 0,
        },
    };
    for (section_headers) |shdr| try w.writeStruct(shdr);

    try buf.flush();
}
