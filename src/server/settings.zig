const std = @import("std");
const builtin = @import("builtin");

const ZonElement = @import("../zon.zig").ZonElement;
const main = @import("main");

pub const version = @import("../utils/version.zig");

pub const defaultPort: u16 = 47649;
pub const connectionTimeout = 60_000_000;

pub const entityLookback: i16 = 100;

pub const highestSupportedLod: u3 = 5;

pub var lastVersionString: []const u8 = "";

pub var simulationDistance: u16 = 4;

pub var cpuThreads: ?u64 = null;

pub var anisotropicFiltering: u8 = 4.0;

pub var renderDistance: u16 = 7;

pub var highestLod: u3 = highestSupportedLod;

pub var lastUsedIPAddress: []const u8 = "";

pub var storageTime: i64 = 5000;

pub var updateRepeatSpeed: u31 = 200;

pub var updateRepeatDelay: u31 = 500;

const settingsFile = if (builtin.mode == .Debug) "debug_settings.zig.zon" else if (builtin.headless == true) "server-settings.zig.zon" else "settings.zig.zon";

pub fn init() void {
    const zon: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, settingsFile) catch |err| blk: {
        if (err != error.FileNotFound) {
            std.log.err("Could not read settings file: {s}", .{@errorName(err)});
        }
        break :blk .null;
    };
    defer zon.deinit(main.stackAllocator);

    inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
        if (!is_const) {
            const declType = @TypeOf(@field(@This(), decl.name));
            if (@typeInfo(declType) == .@"struct") {
                @compileError("Not implemented yet.");
            }
            @field(@This(), decl.name) = zon.get(declType, decl.name, @field(@This(), decl.name));
            if (@typeInfo(declType) == .pointer) {
                if (@typeInfo(declType).pointer.size == .slice) {
                    @field(@This(), decl.name) = main.globalAllocator.dupe(@typeInfo(declType).pointer.child, @field(@This(), decl.name));
                } else {
                    @compileError("Not implemented yet.");
                }
            }
        }
    }
}

pub fn deinit() void {
    save();
    inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
        if (!is_const) {
            const declType = @TypeOf(@field(@This(), decl.name));
            if (@typeInfo(declType) == .@"struct") {
                @compileError("Not implemented yet.");
            }
            if (@typeInfo(declType) == .pointer) {
                if (@typeInfo(declType).pointer.size == .slice) {
                    main.globalAllocator.free(@field(@This(), decl.name));
                } else {
                    @compileError("Not implemented yet.");
                }
            }
        }
    }
}

pub fn save() void {
    var zonObject = ZonElement.initObject(main.stackAllocator);
    defer zonObject.deinit(main.stackAllocator);

    inline for (@typeInfo(@This()).@"struct".decls) |decl| {
        if (comptime std.mem.eql(u8, decl.name, "lastVersionString")) {
            zonObject.put(decl.name, version.version);
            continue;
        }
        const is_const = @typeInfo(@TypeOf(&@field(@This(), decl.name))).pointer.is_const; // Sadly there is no direct way to check if a declaration is const.
        if (!is_const) {
            const declType = @TypeOf(@field(@This(), decl.name));
            if (@typeInfo(declType) == .@"struct") {
                @compileError("Not implemented yet.");
            }
            if (declType == []const u8) {
                zonObject.putOwnedString(decl.name, @field(@This(), decl.name));
            } else {
                zonObject.put(decl.name, @field(@This(), decl.name));
            }
        }
    }

    // Merge with the old settings file to preserve unknown settings.
    var oldZonObject: ZonElement = main.files.cubyzDir().readToZon(main.stackAllocator, settingsFile) catch |err| blk: {
        if (err != error.FileNotFound) {
            std.log.err("Could not read settings file: {s}", .{@errorName(err)});
        }
        break :blk .null;
    };
    defer oldZonObject.deinit(main.stackAllocator);

    if (oldZonObject == .object) {
        oldZonObject.join(zonObject);
    } else {
        oldZonObject.deinit(main.stackAllocator);
        oldZonObject = zonObject;
        zonObject = .null;
    }

    main.files.cubyzDir().writeZon(settingsFile, oldZonObject) catch |err| {
        std.log.err("Couldn't write settings to file: {s}", .{@errorName(err)});
    };
}

pub const launchConfig = struct {
    pub var cubyzDir: []const u8 = "";
    pub var worldName: []const u8 = "";
    pub var gameMode: main.game.Gamemode = .survival;
    pub var allowCheats: bool = false;
    pub fn init() void {
        const zon: ZonElement = main.files.cwd().readToZon(main.stackAllocator, "launchConfig.zon") catch |err| blk: {
            std.log.err("Could not read launchConfig.zon: {s}", .{@errorName(err)});
            break :blk .null;
        };
        defer zon.deinit(main.stackAllocator);

        cubyzDir = main.globalAllocator.dupe(u8, zon.get([]const u8, "cubyzDir", cubyzDir));
        worldName = main.globalAllocator.dupe(u8, zon.get([]const u8, "worldName", worldName));
        var gameModeU8: []const u8 = "";
        gameModeU8 = main.globalAllocator.dupe(u8, zon.get([]const u8, "gameMode", gameModeU8));
        if (std.mem.eql(u8, gameModeU8, "creative")) {
            gameMode = .creative;
        } else {
            gameMode = .survival;
        }
        allowCheats = zon.get(bool, "allowCheats", allowCheats);
    }

    pub fn deinit() void {
        main.globalAllocator.free(cubyzDir);
    }
};
