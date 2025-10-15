const std = @import("std");
pub const build_options = @import("build_options");
pub const server = @import("server/server.zig");

pub const assets = @import("assets.zig");
pub const blocks = @import("blocks.zig");
pub const block_entity = @import("block_entity.zig");
pub const blueprint = @import("blueprint.zig");
pub const chunk = @import("chunk.zig");
pub const files = @import("files.zig");
pub const game = @import("game_common.zig");
pub const items = @import("items.zig");
pub const itemdrop = @import("itemdrop.zig");
pub const JsonElement = @import("json.zig").JsonElement;
pub const migrations = @import("migrations.zig");
pub const models = @import("models.zig");
pub const network = @import("network.zig");
pub const random = @import("random.zig");
// pub const renderer = @import("renderer.zig");
pub const settings = @import("server/settings.zig");
const tag = @import("tag.zig");
pub const Tag = tag.Tag;
pub const utils = @import("utils.zig");
pub const vec = @import("vec.zig");
pub const ZonElement = @import("zon.zig").ZonElement;

pub const heap = @import("utils/heap.zig");

pub const List = @import("utils/list.zig").List;
pub const ListUnmanaged = @import("utils/list.zig").ListUnmanaged;
pub const MultiArray = @import("utils/list.zig").MultiArray;

const file_monitor = utils.file_monitor;

const Vec2f = vec.Vec2f;
const Vec3d = vec.Vec3d;

pub threadlocal var stackAllocator: heap.NeverFailingAllocator = undefined;
pub threadlocal var seed: u64 = undefined;
threadlocal var stackAllocatorBase: heap.StackAllocator = undefined;
var global_gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
var handled_gpa = heap.ErrorHandlingAllocator.init(global_gpa.allocator());
pub const globalAllocator: heap.NeverFailingAllocator = handled_gpa.allocator();
pub var threadPool: *utils.ThreadPool = undefined;

pub fn initThreadLocals() void {
    seed = @bitCast(@as(i64, @truncate(std.time.nanoTimestamp())));
    stackAllocatorBase = heap.StackAllocator.init(globalAllocator, 1 << 23);
    stackAllocator = stackAllocatorBase.allocator();
    heap.GarbageCollection.addThread();
}

pub fn deinitThreadLocals() void {
    stackAllocatorBase.deinit();
    heap.GarbageCollection.removeThread();
}

fn cacheStringImpl(comptime len: usize, comptime str: [len]u8) []const u8 {
    return str[0..len];
}

fn cacheString(comptime str: []const u8) []const u8 {
    return cacheStringImpl(str.len, str[0..].*);
}
var logFile: ?std.fs.File = undefined;
var logFileTs: ?std.fs.File = undefined;
var supportsANSIColors: bool = undefined;
var openingErrorWindow: bool = false;
// overwrite the log function:
pub const std_options: std.Options = .{ // MARK: std_options
    .log_level = .debug,
    .logFn = struct {
        pub fn logFn(
            comptime level: std.log.Level,
            comptime _: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            const color = comptime switch (level) {
                std.log.Level.err => "\x1b[31m",
                std.log.Level.info => "",
                std.log.Level.warn => "\x1b[33m",
                std.log.Level.debug => "\x1b[37;44m",
            };
            const colorReset = "\x1b[0m\n";
            const filePrefix = "[" ++ comptime level.asText() ++ "]" ++ ": ";
            const fileSuffix = "\n";
            comptime var formatString: []const u8 = "";
            comptime var i: usize = 0;
            comptime var mode: usize = 0;
            comptime var sections: usize = 0;
            comptime var sectionString: []const u8 = "";
            comptime var sectionResults: []const []const u8 = &.{};
            comptime var sectionId: []const usize = &.{};
            inline while (i < format.len) : (i += 1) {
                if (mode == 0) {
                    if (format[i] == '{') {
                        if (format[i + 1] == '{') {
                            sectionString = sectionString ++ "{{";
                            i += 1;
                            continue;
                        } else {
                            mode = 1;
                            formatString = formatString ++ "{s}{";
                            sectionResults = sectionResults ++ &[_][]const u8{sectionString};
                            sectionString = "";
                            sectionId = sectionId ++ &[_]usize{sections};
                            sections += 1;
                            continue;
                        }
                    } else {
                        sectionString = sectionString ++ format[i .. i + 1];
                    }
                } else {
                    formatString = formatString ++ format[i .. i + 1];
                    if (format[i] == '}') {
                        sections += 1;
                        mode = 0;
                    }
                }
            }
            formatString = formatString ++ "{s}";
            sectionResults = sectionResults ++ &[_][]const u8{sectionString};
            sectionId = sectionId ++ &[_]usize{sections};
            sections += 1;
            formatString = comptime cacheString("{s}" ++ formatString ++ "{s}");

            comptime var types: []const type = &.{};
            comptime var i_1: usize = 0;
            comptime var i_2: usize = 0;
            inline while (types.len != sections) {
                if (i_2 < sectionResults.len) {
                    if (types.len == sectionId[i_2]) {
                        types = types ++ &[_]type{[]const u8};
                        i_2 += 1;
                        continue;
                    }
                }
                const TI = @typeInfo(@TypeOf(args[i_1]));
                if (@TypeOf(args[i_1]) == comptime_int) {
                    types = types ++ &[_]type{i64};
                } else if (@TypeOf(args[i_1]) == comptime_float) {
                    types = types ++ &[_]type{f64};
                } else if (TI == .pointer and TI.pointer.size == .slice and TI.pointer.child == u8) {
                    types = types ++ &[_]type{[]const u8};
                } else if (TI == .int and TI.int.bits <= 64) {
                    if (TI.int.signedness == .signed) {
                        types = types ++ &[_]type{i64};
                    } else {
                        types = types ++ &[_]type{u64};
                    }
                } else {
                    types = types ++ &[_]type{@TypeOf(args[i_1])};
                }
                i_1 += 1;
            }
            types = &[_]type{[]const u8} ++ types ++ &[_]type{[]const u8};

            const ArgsType = std.meta.Tuple(types);
            comptime var comptimeTuple: ArgsType = undefined;
            comptime var len: usize = 0;
            i_1 = 0;
            i_2 = 0;
            inline while (len != sections) : (len += 1) {
                if (i_2 < sectionResults.len) {
                    if (len == sectionId[i_2]) {
                        comptimeTuple[len + 1] = sectionResults[i_2];
                        i_2 += 1;
                        continue;
                    }
                }
                i_1 += 1;
            }
            comptimeTuple[0] = filePrefix;
            comptimeTuple[comptimeTuple.len - 1] = fileSuffix;
            var resultArgs: ArgsType = comptimeTuple;
            len = 0;
            i_1 = 0;
            i_2 = 0;
            inline while (len != sections) : (len += 1) {
                if (i_2 < sectionResults.len) {
                    if (len == sectionId[i_2]) {
                        i_2 += 1;
                        continue;
                    }
                }
                resultArgs[len + 1] = args[i_1];
                i_1 += 1;
            }

            logToFile(formatString, resultArgs);

            if (supportsANSIColors) {
                resultArgs[0] = color;
                resultArgs[resultArgs.len - 1] = colorReset;
            }
            logToStdErr(formatString, resultArgs);
        }
    }.logFn,
};

fn initLogging() void {
    logFile = null;
    files.cwd().makePath("logs") catch |err| {
        std.log.err("Couldn't create logs folder: {s}", .{@errorName(err)});
        return;
    };
    logFile = std.fs.cwd().createFile("lolatest.log", .{}) catch |err| {
        std.log.err("Couldn't create lolatest.log: {s}", .{@errorName(err)});
        return;
    };

    const _timestamp = std.time.timestamp();

    const _path_str = std.fmt.allocPrint(stackAllocator.allocator, "lots_{}.log", .{_timestamp}) catch unreachable;
    defer stackAllocator.free(_path_str);

    logFileTs = std.fs.cwd().createFile(_path_str, .{}) catch |err| {
        std.log.err("Couldn't create {s}: {s}", .{ _path_str, @errorName(err) });
        return;
    };

    supportsANSIColors = std.fs.File.stdout().supportsAnsiEscapeCodes();
}

fn deinitLogging() void {
    if (logFile) |_logFile| {
        _logFile.close();
        logFile = null;
    }

    if (logFileTs) |_logFileTs| {
        _logFileTs.close();
        logFileTs = null;
    }
}

fn logToFile(comptime format: []const u8, args: anytype) void {
    var buf: [65536]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    const string = std.fmt.allocPrint(allocator, format, args) catch format;
    defer allocator.free(string);
    (logFile orelse return).writeAll(string) catch {};
    (logFileTs orelse return).writeAll(string) catch {};
}

fn logToStdErr(comptime format: []const u8, args: anytype) void {
    var buf: [65536]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    const string = std.fmt.allocPrint(allocator, format, args) catch format;
    defer allocator.free(string);
    const writer = std.debug.lockStderrWriter(&.{});
    defer std.debug.unlockStderrWriter();
    nosuspend writer.writeAll(string) catch {};
}

// MARK: Callbacks

fn isValidIdentifierName(str: []const u8) bool { // TODO: Remove after #480
    if (str.len == 0) return false;
    if (!std.ascii.isAlphabetic(str[0]) and str[0] != '_') return false;
    for (str[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }
    return true;
}

fn isHiddenOrParentHiddenPosix(path: []const u8) bool {
    var iter = std.fs.path.componentIterator(path) catch |err| {
        std.log.err("Cannot iterate on path {s}: {s}!", .{ path, @errorName(err) });
        return false;
    };
    while (iter.next()) |component| {
        if (std.mem.eql(u8, component.name, ".") or std.mem.eql(u8, component.name, "..")) {
            continue;
        }
        if (component.name.len > 0 and component.name[0] == '.') {
            return true;
        }
    }
    return false;
}
pub fn convertJsonToZon(jsonPath: []const u8) void { // TODO: Remove after #480
    if (isHiddenOrParentHiddenPosix(jsonPath)) {
        std.log.info("NOT converting {s}.", .{jsonPath});
        return;
    }
    std.log.info("Converting {s}:", .{jsonPath});
    const jsonString = files.cubyzDir().read(stackAllocator, jsonPath) catch |err| {
        std.log.err("Could convert file {s}: {s}", .{ jsonPath, @errorName(err) });
        return;
    };
    defer stackAllocator.free(jsonString);
    var zonString = List(u8).init(stackAllocator);
    defer zonString.deinit();
    std.log.debug("{s}", .{jsonString});

    var i: usize = 0;
    while (i < jsonString.len) : (i += 1) {
        switch (jsonString[i]) {
            '\"' => {
                var j = i + 1;
                while (j < jsonString.len and jsonString[j] != '"') : (j += 1) {}
                const string = jsonString[i + 1 .. j];
                if (isValidIdentifierName(string)) {
                    zonString.append('.');
                    zonString.appendSlice(string);
                } else {
                    zonString.append('"');
                    zonString.appendSlice(string);
                    zonString.append('"');
                }
                i = j;
            },
            '[', '{' => {
                zonString.append('.');
                zonString.append('{');
            },
            ']', '}' => {
                zonString.append('}');
            },
            ':' => {
                zonString.append('=');
            },
            else => |c| {
                zonString.append(c);
            },
        }
    }
    const zonPath = std.fmt.allocPrint(stackAllocator.allocator, "{s}.zig.zon", .{jsonPath[0 .. std.mem.lastIndexOfScalar(u8, jsonPath, '.') orelse unreachable]}) catch unreachable;
    defer stackAllocator.free(zonPath);
    std.log.info("Outputting to {s}:", .{zonPath});
    std.log.debug("{s}", .{zonString.items});
    files.cubyzDir().write(zonPath, zonString.items) catch |err| {
        std.log.err("Got error while writing to file: {s}", .{@errorName(err)});
        return;
    };
    std.log.info("Deleting file {s}", .{jsonPath});
    files.cubyzDir().deleteFile(jsonPath) catch |err| {
        std.log.err("Got error while deleting file: {s}", .{@errorName(err)});
        return;
    };
}

pub fn main() void { // MARK: main()
    defer if (global_gpa.deinit() == .leak) {
        std.log.err("Memory leak", .{});
    };
    defer heap.GarbageCollection.assertAllThreadsStopped();
    initThreadLocals();
    defer deinitThreadLocals();

    initLogging();
    defer deinitLogging();

    if (files.cwd().openFile("settings.json")) |file| blk: { // TODO: Remove after #480
        file.close();
        std.log.warn("Detected old game client. Converting all .json files to .zig.zon", .{});
        var dir = files.cwd().openIterableDir(".") catch |err| {
            std.log.err("Could not open game directory to convert json files: {s}. Conversion aborted", .{@errorName(err)});
            break :blk;
        };
        defer dir.close();

        var walker = dir.walk(stackAllocator);
        defer walker.deinit();
        while (walker.next() catch |err| {
            std.log.err("Got error while iterating through json files directory: {s}", .{@errorName(err)});
            break :blk;
        }) |entry| {
            if (entry.kind == .file and (std.ascii.endsWithIgnoreCase(entry.basename, ".json") or std.mem.eql(u8, entry.basename, "world.dat")) and !std.ascii.startsWithIgnoreCase(entry.path, "compiler") and !std.ascii.startsWithIgnoreCase(entry.path, ".zig-cache") and !std.ascii.startsWithIgnoreCase(entry.path, ".vscode")) {
                convertJsonToZon(entry.path);
            }
        }
    } else |_| {}

    std.log.info("Starting game client with version {s}", .{settings.version.version});

    settings.launchConfig.init();
    defer settings.launchConfig.deinit();

    files.init();
    defer files.deinit();

    // Background image migration, should be removed after version 0 (#480)
    if (files.cwd().hasDir("assebackgrounds")) moveBlueprints: {
        std.fs.rename(std.fs.cwd(), "assebackgrounds", files.cubyzDir().dir, "backgrounds") catch |err| {
            const notification = std.fmt.allocPrint(stackAllocator.allocator, "Encountered error while moving backgrounds: {s}\nYou may have to move your assebackgrounds manually to {s}/backgrounds", .{ @errorName(err), files.cubyzDirStr() }) catch unreachable;
            defer stackAllocator.free(notification);
            break :moveBlueprints;
        };
        std.log.info("Moved backgrounds to {backgrounds", .{files.cubyzDirStr()});
    }

    settings.init();
    defer settings.deinit();

    threadPool = utils.ThreadPool.init(globalAllocator, settings.cpuThreads orelse @max(1, (std.Thread.getCpuCount() catch 4) -| 1));
    defer threadPool.deinit();

    file_monitor.init();
    defer file_monitor.deinit();

    utils.initDynamicIntArrayStorage();
    defer utils.deinitDynamicIntArrayStorage();

    tag.init();
    defer tag.deinit();

    assets.init();
    defer assets.deinit();

    blocks.init();
    defer blocks.deinit();

    block_entity.init();
    defer block_entity.deinit();

    chunk.init();
    defer chunk.deinit();

    items.globalInit();
    defer items.deinit(0);

    itemdrop.ItemDropManager.init();
    defer itemdrop.ItemDropManager.deinit();

    models.init();
    defer models.deinit();

    network.init();

    // Save migration, should be removed after version 0 (#480)
    if (files.cwd().hasDir("saves")) moveSaves: {
        std.fs.rename(std.fs.cwd(), "saves", files.cubyzDir().dir, "saves") catch |err| {
            const notification = std.fmt.allocPrint(stackAllocator.allocator, "Encountered error while moving saves: {s}\nYou may have to move your saves manually to {saves", .{ @errorName(err), files.cubyzDirStr() }) catch unreachable;
            defer stackAllocator.free(notification);
            break :moveSaves;
        };
        const notification = std.fmt.allocPrint(stackAllocator.allocator, "Your saves have been moved from saves to {saves", .{files.cubyzDirStr()}) catch unreachable;
        defer stackAllocator.free(notification);
    }

    // Blueprint migration, should be removed after version 0 (#480)
    if (files.cwd().hasDir("blueprints")) moveBlueprints: {
        std.fs.rename(std.fs.cwd(), "blueprints", files.cubyzDir().dir, "blueprints") catch |err| {
            std.log.err("Encountered error while moving blueprints: {s}\nYou may have to move your blueprints manually to {blueprints", .{ @errorName(err), files.cubyzDirStr() });
            break :moveBlueprints;
        };
        std.log.info("Moved blueprints to {blueprints", .{files.cubyzDirStr()});
    }

    server.terrain.globalInit();
    defer server.terrain.globalDeinit();

    std.log.info("Starting game server with version {s}", .{settings.version.version});
    const allocator = std.heap.page_allocator;
    const world_dir_result = std.fs.path.join(
        allocator,
        &.{ settings.launchConfig.cubyzDir, "saves", settings.launchConfig.worldName },
    ) catch |err| {
        std.log.err("Could not join path: {s}", .{@errorName(err)});
        return;
    };
    const world_dir = world_dir_result;
    defer allocator.free(world_dir);
    var world_found = true;
    std.fs.cwd().access(world_dir, .{}) catch |e| switch (e) {
        error.FileNotFound => world_found = false,
        else => return,
    };
    if (!world_found) {
        server.save_creator.flawedCreateWorld(settings.launchConfig.worldName, settings.launchConfig.gameMode, settings.launchConfig.allowCheats, false) catch |e| switch (e) {
            else => return,
        };
    }
    const savesDir = std.fs.path.join(allocator, &.{ settings.launchConfig.cubyzDir, "saves" }) catch |e| switch (e) {
        else => return,
    };
    defer allocator.free(savesDir);
    _ = std.fs.cwd().makeDir(savesDir) catch {};

    const assetsDir = std.fs.path.join(allocator, &.{ settings.launchConfig.cubyzDir, "saves", settings.launchConfig.worldName, "assets" }) catch |e| switch (e) {
        else => return,
    };
    defer allocator.free(assetsDir);
    _ = std.fs.cwd().makePath(assetsDir) catch {};
    server.start(settings.launchConfig.worldName, null);
}

// std.testing.refAllDeclsRecursive, but ignores C imports (by name)
pub fn refAllDeclsRecursiveExceptCImports(comptime T: type) void {
    if (!@import("builtin").is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| blk: {
        if (comptime std.mem.eql(u8, decl.name, "c")) continue;
        if (comptime std.mem.eql(u8, decl.name, "hbft")) break :blk;
        if (comptime std.mem.eql(u8, decl.name, "stb_image")) break :blk;
        // TODO: Remove this after Zig removes Managed hashmap PixelGuys/Cubyz#308
        if (comptime std.mem.eql(u8, decl.name, "Managed")) continue;
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursiveExceptCImports(@field(T, decl.name)),
                else => {},
            }
        }
        _ = &@field(T, decl.name);
    }
}

test "abc" {
    @setEvalBranchQuota(1000000);
    refAllDeclsRecursiveExceptCImports(@This());
    _ = @import("json.zig");
    _ = @import("zon.zig");
}
