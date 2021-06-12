const std = @import("std");
const stdout = std.io.getStdOut().writer();
const File = std.fs.File;

const expect = @import("std").testing.expect;

var memory: [4096]u8 = undefined;
var display: [32 * 64]u32 = undefined;
var program_counter: u16 = undefined;
var index_register: u16 = undefined;
var stack: [51]u16 = undefined;
var delay_timer: u8 = undefined;
var sound_timer: u8 = undefined;
var register: [16]u8 = undefined;
const font = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
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
        var xpos = register[vx] % 32;
        var ypos = register[vy] % 64;
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

test "execute jump" {
    execute(0x10, 0x00);
    try expect(program_counter == 0x0);

    execute(0x1f, 0xff);
    try expect(program_counter == 0x0fff);
}

test "execute set register" {
    for (register) |_, i| {
        execute(0x60 + @truncate(u8, i), 0xff);
        try expect(register[i] == 0xff);
    }
}

test "execute set index register" {
    execute(0xaf, 0xff);
    try expect(index_register == 0xfff);
    execute(0xa1, 0x23);
    try expect(index_register == 0x123);
}

test "execute add" {
    register[0] = 0;
    execute(0x70, 0x01);
    try expect(register[0] == 1);

    register[1] = 1;
    execute(0x71, 0x01);
    try expect(register[1] == 2);

    register[0xf] = 0x10;
    execute(0x7f, 0x0a);
    try expect(register[0xf] == 0x1a);
}

fn refreshDisplay() !void {
    //    stdout.print("\x1bc", .{}) catch {};
    var i: i32 = 0;
    for (display) |e| {
        if (e != 0) {
            try stdout.print("*", .{});
        } else {
            try stdout.print(" ", .{});
        }
        if (i == 32) {
            try stdout.print("\n", .{});
            i = 0;
        } else {
            i += 1;
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
