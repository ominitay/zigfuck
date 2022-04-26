// This is not complete -- only needed values are present.

const std = @import("std");

const magic = "\x7fELF".*;
pub const base_addr = 0x400000;

pub const Header = extern struct {
    magic: [4]u8 = magic,
    class: Class,
    endian: Endian,
    header_version: u8 = 1,
    abi: Abi = .sysv,
    abi_version: u8 = 0,
    padding: [7]u8 = .{0} ** 7,
    type: Type,
    arch: Arch,
    elf_version: u32 = 1,
    entry: u64,
    phdr_off: u64 = @sizeOf(Header), // usually immediately following the elf header
    shdr_off: u64,
    flags: [4]u8 = .{0} ** 4,
    hdr_size: u16 = @sizeOf(Header),
    phdr_ent_size: u16 = @sizeOf(ProgramHeader),
    phdr_ent_count: u16,
    shdr_ent_size: u16 = @sizeOf(SectionHeader),
    shdr_ent_count: u16,
    shdr_str_index: u16,

    const Class = enum(u8) {
        @"32" = 1,
        @"64" = 2,
    };

    const Endian = enum(u8) {
        little = 1,
        big = 2,
    };

    const Abi = enum(u8) {
        sysv = 0,
    };

    const Type = enum(u16) {
        relocatable = 1,
        executable = 2,
        shared = 3,
        core = 4,
    };

    const Arch = enum(u16) {
        x64 = 0x3E,
    };
};

pub const ProgramHeader = extern struct {
    type: Type,
    flags: Flags,
    offset: u64,
    virt_addr: u64,
    phys_addr: u64,
    file_size: u64,
    mem_size: u64,
    alignment: u64,

    const Type = enum(u32) {
        @"null" = 0,
        loadable = 1,
        dynamic = 2,
        interp = 3,
        note = 4,
        phdr = 6,
        tls = 7,
    };

    const Flags = packed struct {
        executable: bool = false,
        writable: bool = false,
        readable: bool = false,
        _: u29 = 0,
    };
};

pub const SectionHeader = extern struct {
    name: u32,
    type: Type,
    flags: Flags,
    addr: u64,
    offset: u64,
    size: u64,
    link: u32,
    info: u32,
    alignment: u64,
    entry_size: u64,

    const Type = enum(u32) {
        @"null" = 0,
        prog_bits = 1,
        string_table = 3,
        no_bits = 8,
    };

    const Flags = packed struct {
        writable: bool = false,
        alloc: bool = false,
        executable: bool = false,
        _: u61 = 0,
    };
};

test "Header size" {
    try std.testing.expect(@sizeOf(Header) == 64);
    try std.testing.expect(@sizeOf(ProgramHeader) == 56);
    try std.testing.expect(@sizeOf(SectionHeader) == 64);
}
