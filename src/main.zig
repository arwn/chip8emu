const std = @import("std");
const stdout = std.io.getStdOut().writer();
const File = std.fs.File;

const expect = @import("std").testing.expect;
const rl = @cImport({
    @cInclude("raylib.h");
});

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
var keyboard = [16]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false };

pub fn main() anyerror!void {
    @memcpy(memory[0x50 .. 0x50 + 0xf * 5], font[0 .. 0xf * 5]);
    program_counter = 0x200;

    rl.InitWindow(800, 450, "chip8emu");

    try load();
    try mainLoop();
}

fn mainLoop() !void {
    while (!rl.WindowShouldClose()) {
        refreshDisplay();

        // do vm crap

        const byte_a = memory[program_counter];
        const byte_b = memory[program_counter + 1];
        const instruction: u16 = (@as(u16, byte_a) << 8) | @as(u16, byte_b);
        try stdout.print("Executing instruction {x}\n", .{instruction});
        execute(instruction);
    }
    rl.CloseWindow();
}

fn refreshDisplay() void {
    rl.BeginDrawing();
    rl.ClearBackground(rl.WHITE);
    rl.DrawPixel(100, 100, rl.BLACK);
    for (display, 0..) |e, i| {
        const column: i32 = @intCast(i / 64);
        const row: i32 = @intCast(i % 64);
        if (e != 0) {
            // rl.DrawPixel(row, column, rl.BLACK);
            rl.DrawRectangle(row * 10, column * 10, 10, 10, rl.RED);
        }
    }
    rl.EndDrawing();
}

fn execute(instruction: u16) void {
    switch (instruction & 0xf000) {
        0x0000 => {
            if (instruction == 0x00e0) {
                // 00E0 - CLS
                program_counter += 2;
            } else if (instruction == 0x00ee) {
                // 00E0 - RET
                stack_pointer -= 1;
                program_counter = stack[stack_pointer];
            } else {
                unreachable;
            }
        },

        // 1nnn - JP addr
        0x1000 => program_counter = instruction & 0x0fff,

        // 2nnn - CALL addr
        0x2000 => {
            const jump_to = instruction & 0x0fff;
            stack[stack_pointer] = program_counter;
            stack_pointer += 1;
            program_counter = jump_to;
        },

        // 3xkk - SE Vx, byte
        0x3000 => {
            const x = (instruction & 0x0f00) >> 8;
            const kk = instruction & 0x00ff;
            if (register[x] == kk) {
                program_counter += 4;
            } else {
                program_counter += 2;
            }
        },

        // 4xkk - SNE Vx, byte
        0x4000 => {
            const x = (instruction & 0x0f00) >> 8;
            const kk = (instruction & 0x00ff);
            if (register[x] != kk) {
                program_counter += 4;
            } else {
                program_counter += 2;
            }
        },

        // 5xy0 - SE Vx, Vy
        0x5000 => {
            const x = (instruction & 0x0f00) >> 8;
            const y = (instruction & 0x00f0) >> 4;
            if (register[x] == register[y]) {
                program_counter += 4;
            } else {
                program_counter += 2;
            }
        },

        // 6xkk - LD Vx, byte
        0x6000 => {
            const x = (instruction & 0x0f00) >> 8;
            const kk: u8 = @truncate(instruction & 0x00ff);
            register[x] = kk;
            program_counter += 2;
        },

        // 7xkk - ADD Vx, byte
        0x7000 => {
            const r = (instruction & 0x0f00) >> 8;
            const value = instruction & 0x00ff;
            // _ = @addWithOverflow(u8, register[r], @truncate(u8, value), &register[r]);
            const v: u8 = @truncate(value);
            const added = @addWithOverflow(register[r], v);
            register[r] = added[0];

            program_counter += 2;
        },

        0x8000 => {
            const x = (instruction & 0x0f00) >> 8;
            const y = (instruction & 0x00f0) >> 4;
            switch (instruction & 0x000f) {
                // 8xy0 - LD Vx, Vy
                0x0000 => register[x] = register[y],

                // 8xy1 - OR Vx, Vy
                0x0001 => register[x] |= register[y],

                // 8xy2 - AND Vx, Vy
                0x0002 => register[x] &= register[y],

                // 8xy3 - XOR Vx, Vy
                0x0003 => register[x] ^= register[y],

                // 8xy4 - ADD Vx, Vy
                0x0004 => {
                    const added = @addWithOverflow(register[x], register[y]);
                    register[x] = added[0];
                    // if (@addWithOverflow(u8, register[x], register[y], &register[x])) {
                    if (added[1] == 1) {
                        register[0xf] = 1;
                    } else {
                        register[0xf] = 0;
                    }
                },

                // 8xy5 - SUB Vx, Vy
                0x0005 => {
                    // if (@subWithOverflow(u8, register[x], register[y], &register[x])) {
                    const subed = @subWithOverflow(register[x], register[y]);
                    register[x] = subed[0];
                    if (subed[1] == 1) {
                        register[0xf] = 0;
                    } else {
                        register[0xf] = 1;
                    }
                },

                // 8xy6 - SHR Vx{, Vy}
                0x0006 => {
                    register[0xf] = register[x] & 1;
                    register[x] >>= 1;
                },

                // 8xy7 - SUBN Vx, Vy
                0x0007 => {
                    // if (@subWithOverflow(u8, register[y], register[x], &register[x])) {
                    const subed = @subWithOverflow(register[x], register[y]);
                    register[x] = subed[0];
                    if (subed[1] == 1) {
                        register[0xf] = 1;
                    } else {
                        register[0xf] = 0;
                    }
                },

                // 8xyE - SHL Vx{, Vy}
                0x000e => {
                    // if (@shlWithOverflow(u8, register[x], 1, &register[x])) {
                    const shld = @shlWithOverflow(register[x], 1);
                    register[x] = shld[0];
                    if (shld[1] == 1) {
                        register[0xf] = 1;
                    } else {
                        register[0xf] = 0;
                    }
                },

                else => unreachable,
            }
            program_counter += 2;
        },

        // 9xy0 - SNE Vx, Vy
        0x9000 => {
            const x = (instruction & 0x0f00) >> 8;
            const y = (instruction & 0x00f0) >> 4;
            if (register[x] != register[y]) {
                program_counter += 4;
            } else {
                program_counter += 2;
            }
        },

        // Annn - LD I, addr
        0xa000 => {
            index_register = instruction & 0x0fff;
            program_counter += 2;
        },

        // Bnnn - JP V0, addr
        0xb000 => {
            const nnn = instruction & 0x0fff;
            program_counter = register[0] + nnn;
        },

        // Cxkk - RND Vx, byte
        0xc000 => {
            const x = (instruction & 0x0f00) >> 8;
            const kk: u8 = @truncate(instruction);
            const random_byte = 8;
            register[x] = kk & random_byte;
            program_counter += 2;
        },

        //
        0xD000 => {
            const x = register[(instruction & 0x0F00) >> 8];
            const y = register[(instruction & 0x00F0) >> 4];
            const n = instruction & 0x000F;
            const width = 64;
            const height = 32;

            register[0xF] = 0x0;
            var row: usize = 0;
            while (row < n) : (row += 1) {
                const sprite_byte: u8 = memory[index_register + row];

                var col: u8 = 0;
                while (col < 8) : (col += 1) {
                    const truncated: u3 = @truncate(7 - col);
                    const sprite_pixel = sprite_byte >> truncated & 0x01;
                    const screen_pixel = &display[((y + row) % height) * width + (@addWithOverflow(x, col)[0] % width)];

                    // Sprite pixel is on
                    if (sprite_pixel == 0x1) {
                        // screen pixel is also on
                        if (screen_pixel.* == 0x1) {
                            register[0xF] = 0x1;
                        }
                        screen_pixel.* ^= 0x1;
                    }
                }
            }
            program_counter += 2;
        },

        // Ex9E - SKP Vx
        0xe09e => {
            const keycode = (instruction & 0x0f00) >> 8;
            if (keyboard[keycode]) {
                program_counter += 4;
            } else {
                program_counter += 2;
            }
        },

        0xf000 => {
            switch (instruction & 0x00ff) {
                // ExA1 - SKNP Vx
                0xe0a1 => unreachable,

                // Fx07 - LD Vx, DT
                0xf007 => unreachable,

                // Fx0A - LD Vx, K
                0x000a => {
                    stdout.print("Would wait for key press.\n", .{}) catch {};
                },

                // Fx15 - LD DT, Vx
                0xf015 => unreachable,

                // Fx18 - LD ST, Vx
                0xf018 => unreachable,

                // Fx1E - ADD I, Vx
                0xf01e => {
                    const x = (instruction & 0x0f00) >> 8;
                    const added = @addWithOverflow(index_register, register[x]);
                    index_register = added[0];
                },

                // Fx29 - LD F, Vx
                0x0029 => {
                    const x = (instruction & 0x0f00) >> 8;
                    index_register = register[x] * 5;
                    program_counter += 2;
                },

                // Fx33 - LD B, Vx
                0x0033 => {
                    const x = (instruction & 0x0f00) >> 8;
                    const v = register[x];
                    const ones: u8 = @truncate(v % 10);
                    const tens: u8 = @truncate(v / 10 % 10);
                    const hundreds: u8 = @truncate(v / 100);
                    memory[index_register] = hundreds;
                    memory[index_register + 1] = tens;
                    memory[index_register + 2] = ones;
                    program_counter += 2;
                },

                // Fx55 - LD [I], Vx
                0x0055 => {
                    const x = (instruction & 0x0f00) >> 8;
                    @memcpy(memory[index_register .. index_register + x + 1], register[0 .. x + 1]);
                    program_counter += 2;
                },

                // Fx65 - LD Vx, [I]
                0x0065 => {
                    const x = (instruction & 0x0f00) >> 8;
                    @memcpy(register[0 .. x + 1], memory[index_register .. index_register + x + 1]);
                    program_counter += 2;
                },

                else => {
                    stdout.print("Unreachable instruction {x}\n", .{instruction}) catch {};
                    unreachable;
                },
            }
        },

        else => {
            stdout.print("Unreachable instruction {x}\n", .{instruction}) catch {};
            unreachable;
        },
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
    // const romname = "rom/abc.ch8";
    const romname = "rom/ibm-logo.ch8";
    // const romname = "rom/stars.ch8";
    // const romname = "rom/test_opcode.ch8";
    // const romname = "rom/chip8-test-rom.ch8";
    _ = try std.fs.cwd().readFile(romname, memory[0x200..]);
}

test "execute 00e0 cls" {
    execute(0x00e0);
    for (display) |m| {
        try expect(m == 0);
    }
}

test "execute 00ee ret" {
    stack_pointer = 1;
    const old_sp = stack_pointer;
    program_counter = 1;
    //const old_pc = program_counter;
    execute(0x00ee);
    try expect(stack_pointer == old_sp - 1);
    try expect(stack_pointer == old_sp - 1);
    try expect(program_counter == stack[stack_pointer]);
}

test "execute 1nnn jump" {
    execute(0x1000);
    try expect(program_counter == 0x0);

    execute(0x1fff);
    try expect(program_counter == 0x0fff);
}

test "execute 2nnn call" {
    const old_pc = program_counter;
    const old_sp = stack_pointer;
    execute(0x200f);
    try expect(program_counter == 0x00f);
    try expect(stack_pointer == old_sp + 1);
    try expect(stack[old_sp] == old_pc);
}

test "execute 3xkk skip eq" {
    const old_pc = program_counter;
    register[3] = 1;
    execute(0x3301);
    try expect(old_pc + 4 == program_counter);

    program_counter = old_pc;
    execute(0x33ff);
    try expect(old_pc + 2 == program_counter);
}

test "4xkk - SNE Vx, byte" {
    const old_pc = program_counter;
    register[3] = 1;
    execute(0x4301);
    try expect(old_pc + 2 == program_counter);

    program_counter = old_pc;
    execute(0x43ff);
    try expect(old_pc + 4 == program_counter);
}

test "execute 5xy0 skip if x = y" {
    const old_pc = program_counter;
    register[3] = 0x1;
    register[5] = 0xf;
    execute(0x5350);
    try expect(old_pc + 2 == program_counter);

    program_counter = old_pc;
    register[3] = 0xf;
    register[5] = 0xf;
    execute(0x5350);
    try expect(old_pc + 4 == program_counter);
}

test "execute 6xkk load vx kk" {
    execute(0x64fa);
    try expect(register[4] == 0xfa);

    execute(0x6fee);
    try expect(register[0xf] == 0xee);

    execute(0x6011);
    try expect(register[0x0] == 0x11);
}

test "execute 7xkk add vx kk" {
    register[2] = 1;
    execute(0x7203);
    try expect(register[2] == 4);
}

test "execute 8xy0 ld vx vy" {
    register[1] = 0xaa;
    register[2] = 0xff;
    execute(0x8120);
    try expect(register[1] == register[2]);
    try expect(register[1] == 0xff);
}

test "execute 8xy1 vx or vy" {
    register[1] = 0x10;
    register[2] = 0x1f;
    execute(0x8121);
    try expect(register[1] == 0x10 | 0x1f);
    try expect(register[2] == 0x1f);
}

test "execute 8xy2 vx and vy" {
    register[1] = 0x10;
    register[2] = 0x1f;
    execute(0x8122);
    try expect(register[1] == 0x10 & 0x1f);
    try expect(register[2] == 0x1f);
}

test "execute 8xy3 vx xor vy" {
    register[1] = 0x10;
    register[2] = 0x1f;
    execute(0x8123);
    try expect(register[1] == 0x10 ^ 0x1f);
    try expect(register[2] == 0x1f);
}

test "execute 8xy4 add vx vy" {
    register[1] = 2;
    register[2] = 3;
    execute(0x8124);
    try expect(register[1] == 5);
    try expect(register[2] == 3);

    register[1] = 255;
    register[2] = 1;
    execute(0x8124);
    try expect(register[1] == 0);
    try expect(register[15] == 1);
}

test "execute 8xy5 sub vx vy" {
    register[1] = 5;
    register[2] = 1;
    execute(0x8125);
    try expect(register[1] == 4);
    try expect(register[2] == 1);
    try expect(register[15] == 1);

    register[1] = 4;
    register[2] = 5;
    execute(0x8125);
    try expect(register[1] == 255);
    try expect(register[2] == 5);
    try expect(register[15] == 0);
}

test "execute 8xy6 shr vx" {
    register[1] = 0xfd;
    execute(0x8106);
    try expect(register[1] == 0xfd >> 1);
    try expect(register[15] == 0xfd & 1);

    execute(0x8106);
    try expect(register[1] == 0xfd >> 2);
    try expect(register[15] == (0xfd >> 1) & 1);
}

test "execute 8xy7 subn vx vy" {
    register[1] = 6;
    register[2] = 12;
    execute(0x8127);
    try expect(register[1] == 12 - 6);
    try expect(register[2] == 12);
    try expect(register[15] == 0);

    register[1] = 0;
    register[2] = 0;
    execute(0x8127);
    try expect(register[1] == 0);
    try expect(register[2] == 0);
    try expect(register[15] == 0);
}

test "execute 8xyE shl vx" {
    register[1] = 6;
    execute(0x810E);
    try expect(register[1] == 6 << 1);
    try expect(register[15] == 0);

    register[1] = 0xff;
    execute(0x810E);
    const x: u8 = @truncate(0xff << 1);
    try expect(register[1] == x);
    try expect(register[15] == 1);
}

test "execute skip ne vx vy" {
    const old_pc = program_counter;
    register[1] = 1;
    register[2] = 1;
    execute(0x9120);
    try expect(program_counter == old_pc + 2);

    register[2] = 0xff;
    register[3] = 0;
    execute(0x9230);
    try expect(program_counter == old_pc + 6);
}

test "execute annn load index_register nnn" {
    execute(0xafff);
    try expect(index_register == 0xfff);
    execute(0xa123);
    try expect(index_register == 0x123);
}

test "execute bnnn jump v0 nnn" {
    var old_pc = program_counter;
    register[0] = 0;
    execute(0xbf00);
    try expect(program_counter == 0x0f00);

    old_pc = program_counter;
    register[0] = 3;
    execute(0xbf00);
    try expect(program_counter == 0x0f03);

    old_pc = program_counter;
    register[0] = 3;
    execute(0xbf03);
    try expect(program_counter == 0x0f06);
}

test "execute cxkk rnd vx kk" {
    register[8] = 3;
    execute(0xc800);
    try expect(register[8] == 0);

    register[8] = 0;
    execute(0xc8ff);
    expect(register[8] != 0) catch {
        execute(0xc8ff);
        expect(register[8] != 0) catch {
            execute(0xc8ff);
            try expect(register[8] != 0);
        };
    };
}

test "execute dxyn display vx vy n" {
    // TODO: this
}

test "execute Fx29 - LD F, Vx" {
    memory[0] = 0;
    execute(0xf029);
    try expect(index_register == 0);
}

test "execute Fx33 - LD B, Vx" {
    register[1] = 123;
    execute(0xf133);
    try expect(memory[index_register] == 1);
    try expect(memory[index_register + 1] == 2);
    try expect(memory[index_register + 2] == 3);
}

test "execute Fx55 LD [I], Vx" {
    register[0] = 69;
    register[1] = 96;
    execute(0xf255);
    try expect(memory[index_register] == 69);
    try expect(memory[index_register + 1] == 96);

    index_register += 2;
    register[0] = 1;
    register[1] = 2;
    register[2] = 3;
    register[3] = 4;
    execute(0xf455);
    try expect(memory[index_register - 2] == 69);
    try expect(memory[index_register - 1] == 96);
    try expect(memory[index_register] == 1);
    try expect(memory[index_register + 1] == 2);
    try expect(memory[index_register + 2] == 3);
    try expect(memory[index_register + 3] == 4);
}

test "execute Fx65 - LD Vx, [I]" {
    register[0] = 9;
    register[1] = 9;
    register[2] = 9;
    register[3] = 9;
    index_register = 0;
    memory[index_register] = 0;
    memory[index_register + 1] = 1;
    execute(0xf265);
    try expect(register[0] == 0);
    try expect(register[1] == 1);
    try expect(register[2] == 9);
    try expect(register[3] == 9);
}
