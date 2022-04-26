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
    const out_path = args.next().?;
    std.debug.assert(args.skip() == false);

    var source_file = try std.fs.cwd().openFile(source_path, .{});
    defer source_file.close();

    const source_bytes = try source_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source_bytes);

    var out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true, .mode = 0o775 });
    defer out_file.close();
    const out_writer = out_file.writer();

    try generate(allocator, codegen.x64, source_bytes, out_writer);
}

fn generate(allocator: std.mem.Allocator, cg: anytype, source: []const u8, writer: anytype) !void {
    var bir = try parse(allocator, source);
    try bir.optimise();

    var buf = std.io.bufferedWriter(writer);
    const w = buf.writer();

    const code = try cg.generate(allocator, bir.instructions.items);
    defer allocator.free(code);
    const code_prefix = [_]u8{ 0x49, 0xba } ++ [_]u8{0x00} ** 8; // this is used to load the address of the first cell to r10. the address is copied in later once we know what it will be.
    const shstrtab = "\x00.text\x00.bss\x00.shstrtab\x00".*;
    const section_count = 4;
    const phdr_count = 2;

    const bss_len = cell_count;

    const sections = try std.mem.concat(allocator, u8, &[_][]const u8{ &code_prefix, code, &shstrtab });
    defer allocator.free(sections);

    const header_len = @sizeOf(elf.Header) + phdr_count * @sizeOf(elf.ProgramHeader);

    const text_off = header_len;
    const text_pos = header_len + elf.base_addr;
    const text_len = code.len + code_prefix.len;
    const shstrtab_off = text_off + text_len;
    const section_header_off = shstrtab_off + shstrtab.len;
    const bss_off = shstrtab_off + shstrtab.len;
    const bss_pos = text_pos + text_len;

    std.mem.copy(u8, sections[2..], @bitCast([8]u8, bss_pos)[0..]); // add the correct address for the first cell

    const header = elf.Header{
        .class = .@"64",
        .endian = .little,
        .type = .executable,
        .arch = .x64,
        .entry = text_pos,
        .shdr_off = section_header_off,
        .phdr_ent_count = phdr_count,
        .shdr_ent_count = section_count,
        .shdr_str_index = 2,
    };
    try w.writeStruct(header);

    // FIXME: Correctly align segments (currently blocking us from setting .bss to get proper memory protection)
    const program_headers = [phdr_count]elf.ProgramHeader{
        .{ // phdrs
            .type = .loadable,
            .flags = .{ .readable = true },
            .offset = 0,
            .virt_addr = elf.base_addr,
            .phys_addr = elf.base_addr,
            .file_size = header_len,
            .mem_size = header_len,
            .alignment = 0x8,
        },
        .{ // .text and .bss
            .type = .loadable,
            .flags = .{ .executable = true, .writable = true, .readable = true },
            .offset = text_off,
            .virt_addr = text_pos,
            .phys_addr = text_pos,
            .file_size = text_len,
            .mem_size = text_len + bss_len,
            .alignment = 0x1000,
        },
        // .{ // .bss
        //     .type = .loadable,
        //     .flags = .{ .writable = true, .readable = true },
        //     .offset = bss_off,
        //     .virt_addr = bss_pos,
        //     .phys_addr = bss_pos,
        //     .file_size = 0,
        //     .mem_size = bss_len,
        //     .alignment = 0x1000,
        // },
    };
    for (program_headers) |phdr| try w.writeStruct(phdr);

    try w.writeAll(sections[0..]);

    const text_str = @intCast(u32, std.mem.indexOf(u8, &shstrtab, ".text").?);
    const bss_str = @intCast(u32, std.mem.indexOf(u8, &shstrtab, ".bss").?);
    const shstrtab_str = @intCast(u32, std.mem.indexOf(u8, &shstrtab, ".shstrtab").?);
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
            .name = text_str,
            .type = .prog_bits,
            .flags = .{ .alloc = true, .executable = true },
            .addr = text_pos,
            .offset = text_off,
            .size = text_len,
            .link = 0,
            .info = 0,
            .alignment = 0,
            .entry_size = 0,
        },
        .{ // .shstrtab
            .name = shstrtab_str,
            .type = .string_table,
            .flags = .{},
            .addr = 0,
            .offset = shstrtab_off,
            .size = shstrtab.len,
            .link = 0,
            .info = 0,
            .alignment = 0,
            .entry_size = 0,
        },
        .{ // .bss
            .name = bss_str,
            .type = .no_bits,
            .flags = .{ .writable = true, .alloc = true },
            .addr = bss_pos,
            .offset = bss_off,
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
