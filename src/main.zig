const std = @import("std");
const stdout = std.io.getStdOut().writer();
const File = std.fs.File;

const expect = @import("std").testing.expect;

const SDL = @import("sdl2");

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
    try SDL.init(.{
        .video = true,
        .events = true,
        .audio = true,
    });
    defer SDL.quit();

    var window = try SDL.createWindow(
        "SDL2 Wrapper Demo",
        .{ .centered = {} }, .{ .centered = {} },
        640, 320,
        .{ .shown = true },
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
    defer renderer.destroy();
    try renderer.setScale(10, 10);

    try load();
    try mainLoop(renderer);
}

fn mainLoop(renderer: SDL.Renderer) !void {
    mainLoop: while (true) {
        while (SDL.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                else => {},
            }
        }

       

        // do vm crap
        const byte_a = memory[program_counter];
        const byte_b = memory[program_counter + 1];
        const instruction: u16 = (@as(u16, byte_a) << 8) | @as(u16, byte_b);
        execute(instruction);

        try refreshDisplay(renderer);
    }
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
            // Skip next instruction if Vx != kk.
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
            // Skip next instruction if Vx != kk.  The interpreter
            // compares register Vx to kk, and if they are not
            // equal,increments the program counter by 2.
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
            // Skip next instruction if Vx = Vy.  The interpreter
            // compares register Vx to register Vy, and if they are
            // equal,increments the program counter by 2.
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
            // Set Vx = kk.  The interpreter puts the value kk into
            // register Vx.
            const x = (instruction & 0x0f00) >> 8;
            const kk = @truncate(u8, instruction & 0x00ff);
            register[x] = kk;
            program_counter += 2;
        },

        // 7xkk - ADD Vx, byte
        0x7000 => {
            // Set Vx = Vx + kk.  Adds the value kk to the value of
            // register Vx, then stores the result in Vx.
            const r = (instruction & 0x0f00) >> 8;
            const value = instruction & 0x00ff;
            register[r] += @truncate(u8, value);
            program_counter += 2;
        },

        0x8000 => {
            const x = (instruction & 0x0f00) >> 8;
            const y = (instruction & 0x00f0) >> 4;
            switch (instruction & 0x000f) {
                // 8xy0 - LD Vx, Vy
                0x0000 => {
                    // Set Vx = Vy.
                    register[x] = register[y];
                },

                // 8xy1 - OR Vx, Vy
                0x0001 => {
                    // Set Vx = Vx OR Vy.
                    register[x] |= register[y];
                },

                // 8xy2 - AND Vx, Vy
                0x0002 => {
                    // Set Vx = Vx AND Vy.
                    register[x] &= register[y];
                },

                // 8xy3 - XOR Vx, Vy
                0x0003 => {
                    // Set Vx = Vx XOR Vy.
                    register[x] ^= register[y];
                },

                // 8xy4 - ADD Vx, Vy
                0x0004 => {
                    // Set Vx = Vx + Vy, set VF = carry.  If the
                    // result is greaterthan 8 bits VF is set to 1,
                    // otherwise 0.
                    if (@addWithOverflow(u8, register[x], register[y], &register[x])) {
                        register[0xf] = 1;
                    } else {
                        register[0xf] = 0;
                    }
                },

                // 8xy5 - SUB Vx, Vy
                0x0005 => {
                    // Set Vx = Vx - Vy, set VF = NOT borrow.  If Vx <
                    // Vy, then VF is set to 1, otherwise 0.
                    if (@subWithOverflow(u8, register[x], register[y], &register[x])) {
                        register[0xf] = 0;
                    } else {
                        register[0xf] = 1;
                    }
                },

                // 8xy6 - SHR Vx{, Vy}
                0x0006 => {
                    // Set Vx = Vx SHR 1.  If the least-significant
                    // bit of Vx is 1, then VF is set to 1, otherwise
                    // 0.
                    register[0xf] = register[x] & 1;
                    register[x] >>= 1;
                },

                // 8xy7 - SUBN Vx, Vy
                0x0007 => {
                    // Set Vx = Vy - Vx, set VF = NOT borrow.  If Vy <
                    // Vx, then VF is set to 1, otherwise 0.
                    if (@subWithOverflow(u8, register[y], register[x], &register[x])) {
                        register[0xf] = 1;
                    } else {
                        register[0xf] = 0;
                    }
                },

                // 8xyE - SHL Vx{, Vy}
                0x000e => {
                    // Set Vx = Vx SHL 1.  If the most-significant bit
                    // of Vx is 1, then VF is set to 1, otherwise to
                    // 0.
                    if (@shlWithOverflow(u8, register[x], 1, &register[x])) {
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
            // Skip next instruction if Vx != Vy.
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
            // Set I = nnn.
            index_register = instruction & 0x0fff;
            program_counter += 2;
        },

        // Bnnn - JP V0, addr
        0xb000 => {
            // Jump to location nnn + V0.
            const nnn = instruction & 0x0fff;
            program_counter = register[0] + nnn;
        },

        // Cxkk - RND Vx, byte
        0xc000 => {
            // Set Vx = random byte AND kk.
            const x = (instruction & 0x0f00) >> 8;
            const kk = @truncate(u8, instruction);
            register[x] = kk & 8;
        },

        0xd000 => {
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
            program_counter += 2;
        },

        // Ex9E - SKP Vx
        // TODO: make this actually work
        0xe09e => {
            // Skip next instruction if key with the value of Vx is
            // pressed.
            // const x = (instruction & 0x0f00) >> 8;
            // const keycode = kb.getKey();
            // if (keycode == x) {
            //     program_counter += 4;
            // } else {
            //     program_counter += 2;
            // }
        },

        else => unreachable,
    }
}

fn refreshDisplay(renderer: SDL.Renderer) !void {
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
    // sdl henceforth
    try renderer.setColorRGB(0xF7, 0xA4, 0x1D);
    try renderer.clear();

    try renderer.setColor(SDL.Color.black);
    for (display) |e, i| {
        const column = @intCast(i32, i / 64);
        const row = @intCast(i32, i % 64);
        if (e != 0) {
            try renderer.drawPoint(row, column);
        }
    }

    renderer.present();
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
    try expect(register[1] == @truncate(u8, 0xff << 1));
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
