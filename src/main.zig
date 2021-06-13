const std = @import("std");
const stdout = std.io.getStdOut().writer();
const File = std.fs.File;

const expect = @import("std").testing.expect;

var memory: [4096]u8 = undefined;
var display: [32 * 64]u32 = undefined;
var program_counter: u16 = undefined;
var index_register: u16 = undefined;
var stack: [51]u16 = undefined;
var stack_pointer: u16 = undefined;
var delay_timer: u8 = undefined;
var sound_timer: u8 = undefined;
var register: [16]u8 = undefined;
const font = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0,
    0x20, 0x60, 0x20, 0x20, 0x70,
    0xF0, 0x10, 0xF0, 0x80, 0xF0,
    0xF0, 0x10, 0xF0, 0x10, 0xF0,
    0x90, 0x90, 0xF0, 0x10, 0x10,
    0xF0, 0x80, 0xF0, 0x10, 0xF0,
    0xF0, 0x80, 0xF0, 0x90, 0xF0,
    0xF0, 0x10, 0x20, 0x40, 0x40,
    0xF0, 0x90, 0xF0, 0x90, 0xF0,
    0xF0, 0x90, 0xF0, 0x10, 0xF0,
    0xF0, 0x90, 0xF0, 0x90, 0x90,
    0xE0, 0x90, 0xE0, 0x90, 0xE0,
    0xF0, 0x80, 0x80, 0x80, 0xF0,
    0xE0, 0x90, 0x90, 0x90, 0xE0,
    0xF0, 0x80, 0xF0, 0x80, 0xF0,
    0xF0, 0x80, 0xF0, 0x80, 0x80,
};

pub fn main() anyerror!void {
    @memcpy(memory[0x50..], font[0..], 0xf * 5);
    program_counter = 0x200;
    try load();
    try mainLoop();
}

fn mainLoop() !void {
    var i: i32 = 0;
    while (true) {
        const byte_a = memory[program_counter];
        const byte_b = memory[program_counter + 1];
        execute(byte_a, byte_b);
    }
}

fn execute(byte_a: u8, byte_b: u8) void {
    const instruction: u16 = (@as(u16, byte_a) << 8) | @as(u16, byte_b);

    if (instruction == 0x00e0) {
        program_counter += 2;
    } else if (instruction == 0x00ee) {
        stack_pointer -= 1;
        program_counter = stack[stack_pointer];
    } else if ((instruction & 0xf000) == 0x2000) {
        const jump_to = instruction & 0x0fff;
        stack[stack_pointer] = program_counter;
        stack_pointer += 1;
        program_counter = jump_to;
    } else if ((instruction & 0xf000) == 0xa000) {
        index_register = instruction & 0x0fff;
        program_counter += 2;
    } else if ((instruction & 0xf000) == 0x6000) {
        const r = (instruction & 0x0f00) >> 8;
        const val: u8 = @truncate(u8, instruction & 0x00ff);
        register[r] = val;
        program_counter += 2;
    } else if ((instruction & 0xf000) == 0x7000) {
        const r = (instruction & 0x0f00) >> 8;
        const value = instruction & 0x00ff;
        register[r] += @truncate(u8, value);
        program_counter += 2;
    } else if ((instruction & 0xf000) == 0xd000) {
        const vx: u8 = @truncate(u8, (instruction & 0x0f00) >> 8);
        const vy: u8 = @truncate(u8, (instruction & 0x00f0) >> 4);
        const h: u8 = @truncate(u8, (instruction & 0x000f));
        var xpos = register[vx] % 64;
        var ypos = register[vy] % 32;
        var row: u8 = 0;
        while (row < h) : (row += 1) {
            const sprite_bype = memory[index_register + row];
            var col: u8 = 0;
            while (col < 8) : (col += 1) {
                const x80: u8 = 0x80;
                const s: u8 = x80 >> @truncate(u3, col);
                const sprite_pixel: u8 = sprite_bype & s;
                const screen_pixel: *u32 = &display[@as(u32, (ypos + row)) * 32 + xpos + col];
                if (sprite_pixel != 0) {
                    screen_pixel.* ^= 0xffffffff;
                }
            }
        }
        refreshDisplay() catch {};
        program_counter += 2;
    } else if ((instruction & 0xf000) == 0x1000) {
        program_counter = instruction & 0x0fff;
    } else {
        unreachable;
    }
}

fn refreshDisplay() !void {
    stdout.print("\x1bc", .{}) catch {};
    for (display) |e, i| {
        if (e != 0) {
            try stdout.print("*", .{});
        } else {
            try stdout.print(" ", .{});
        }
        if (i % 64 == 63) {
            try stdout.print("\n", .{});
        }
    }
}

pub fn printMem() !void {
    var line: i5 = 0;
    for (memory) |byte| {
        line +%= 1;
        if (byte == 0) {
            try stdout.print("00", .{});
        } else {
            try stdout.print("{x:2}", .{byte});
        }
        if (line == 0) try stdout.print("\n", .{});
    }
}

fn load() !void {
    const romname = "rom/ibm-logo.ch8";
    _ = try std.fs.cwd().readFile(romname, memory[0x200..]);
}

test "execute 00e0 cls" {
    execute(0x00, 0xe0);
    for (display) |m| {
        try expect(m == 0);
    }
}

test "execute 00ee ret" {
    stack_pointer = 1;
    const old_sp = stack_pointer;
    program_counter = 1;
    const old_pc = program_counter;
    execute(0x00, 0xee);
    try expect(stack_pointer == old_sp - 1);
    try expect(stack_pointer == old_sp - 1);
    try expect(program_counter == stack[stack_pointer]);
}

test "execute 1nnn jump" {
    execute(0x10, 0x00);
    try expect(program_counter == 0x0);

    execute(0x1f, 0xff);
    try expect(program_counter == 0x0fff);
}

test "execute 2nnn call" {
    const old_pc = program_counter;
    const old_sp = stack_pointer;
    execute(0x20, 0x0f);
    try expect(program_counter == 0x00f);
    try expect(stack_pointer == old_sp + 1);
    try expect(stack[old_sp] == old_pc);
}

test "execute 3xkk skip eq" {
    const old_pc = program_counter;
    register[3] = 1;
    execute(0x33, 0x01);
    try expect(old_pc + 4 == program_counter);

    program_counter = old_pc;
    execute(0x33, 0xff);
    try expect(old_pc + 2 == program_counter);
}

test "execute 4xkk skip ne" {
    const old_pc = program_counter;
    register[3] = 1;
    execute(0x43, 0x01);
    try expect(old_pc + 2 == program_counter);

    program_counter = old_pc;
    execute(0x43, 0xff);
    try expect(old_pc + 4 == program_counter);
}

test "execute 5xy0 skip if x = y" {
    const old_pc = program_counter;
    register[3] = 0x1;
    register[5] = 0xf;
    execute(0x53, 0x50);
    try expect(old_pc + 2 == program_counter);

    program_counter = old_pc;
    register[3] = 0xf;
    register[5] = 0xf;
    execute(0x53, 0x50);
    try expect(old_pc + 4 == program_counter);
}

test "execute 6xkk load vx kk" {
    for (register) |_, i| {
        execute(0x60 + @truncate(u8, i), 0xfa);
        try expect(register[i] == 0xfa);
    }
}

test "execute 7xkk add vx kk" {
    register[2] = 1;
    execute(0x72, 0x03);
    try expect(register[2] == 4);
}

test "execute 8xy0 ld vx vy" {
    register[1] = 0xaa;
    register[2] = 0xff;
    execute(0x81, 0x20);
    try expect(register[1] == register[2]);
    try expect(register[1] == 0xff);
}

test "execute 8xy1 vx or vy" {
    register[1] = 0x10;
    register[2] = 0x1f;
    execute(0x81, 0x21);
    try expect(register[1] == 0x10 | 0x1f);
    try expect(register[2] == 0x1f);
}

test "execute 8xy2 vx and vy" {
    register[1] = 0x10;
    register[2] = 0x1f;
    execute(0x81, 0x22);
    try expect(register[1] == 0x10 & 0x1f);
    try expect(register[2] == 0x1f);
}

test "execute 8xy3 vx xor vy" {
    register[1] = 0x10;
    register[2] = 0x1f;
    execute(0x81, 0x23);
    try expect(register[1] == 0x10 ^ 0x1f);
    try expect(register[2] == 0x1f);
}

test "execute 8xy4 add vx vy" {
    register[1] = 2;
    register[2] = 3;
    execute(0x82, 0x34);
    try expect(register[1] == 5);
    try expect(register[15] == 0);

    register[1] = 255;
    register[2] = 1;
    execute(0x82, 0x34);
    try expect(register[1] == 0);
    try expect(register[15] == 1);
}

test "execute 8xy5 sub vx vy" {
    register[1] = 5;
    register[2] = 1;
    execute(0x81, 0x25);
    try expect(register[1] == 4);
    try expect(register[2] == 1);
    try expect(register[15] == 1);

    register[1] = 4;
    register[2] = 5;
    execute(0x81, 0x25);
    try expect(register[1] == 255);
    try expect(register[2] == 2);
    try expect(register[15] == 0);
}

test "execute 8xy6 shr vx" {
    register[1] = 0xfd;
    execute(0x81, 0x06);
    try expect(register[1] == 0xfd >> 1);
    try expect(register[15] == 0xfd & 1);

    execute(0x81, 0x06);
    try expect(register[1] == 0xfd >> 2);
    try expect(register[15] == (0xfd >> 1) & 1);
}

test "execute 8xy7 subn vx vy" {
    register[1] = 12;
    register[2] = 6;
    execute(0x81, 0x27);
    try expect(register[1] == 12 - 6);
    try expect(register[2] == 6);
    try expect(register[15] == 1);

    register[1] = 0;
    register[2] = 0;
    execute(0x81, 0x27);
    try expect(register[1] == 0);
    try expect(register[2] == 0);
    try expect(register[15] == 0);
}

test "execute 8xyE shl vx" {
    register[1] = 6;
    execute(0x81, 0x0E);
    try expect(register[1] == 6 << 1);
    try expect(register[15] == 0);

    register[1] = 0xff;
    execute(0x81, 0x0E);
    try expect(register[1] == 0xff << 1);
    try expect(register[15] == 0);
}

test "execute skip ne vx vy" {
    const old_pc = program_counter;
    register[1] = 1;
    register[2] = 1;
    execute(0x91, 0x20);
    try expect(program_counter == old_pc + 2);

    register[2] = 0xff;
    register[3] = 0;
    execute(0x92, 0x30);
    try expect(program_counter == old_pc + 6);
}

test "execute annn load index_register nnn" {
    execute(0xaf, 0xff);
    try expect(index_register == 0xfff);
    execute(0xa1, 0x23);
    try expect(index_register == 0x123);
}

test "execute bnnn jump v0 nnn" {
    const old_pc = program_counter;
    const v0 = register[0];
    execute(0xbf, 0x00);
    try expect(program_counter == v0 + 0xf00);
}

test "execute cxkk rnd vx kk" {
    // ???
}

test "execute dxyn display vx vy n" {
    // how does one test this?
}
