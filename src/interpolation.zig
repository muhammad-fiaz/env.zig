const std = @import("std");
const osEnv = @import("os_env.zig");

/// Maximum number of interpolation references tracked for cycle detection.
const maxDepthLimit = 64;

/// Resolve variable interpolation in a value string.
/// Replaces ${VAR}, ${VAR:-default}, ${VAR:+alt}, $VAR with values from map or OS env.
/// OS fallback: if not found in vars, checks process environment (cross-platform).
pub fn interpolate(
    allocator: std.mem.Allocator,
    value: []const u8,
    vars: *const std.StringHashMap([]const u8),
    maxDepth: usize,
) (std.mem.Allocator.Error || error{ CircularDependency, MaxDepthExceeded })![]const u8 {
    var seenBuf: [maxDepthLimit][]const u8 = undefined;
    var seenLen: usize = 0;
    return interpolateImpl(allocator, value, vars, maxDepth, 0, &seenBuf, &seenLen);
}

fn lookupVar(name: []const u8, vars: *const std.StringHashMap([]const u8)) ?[]const u8 {
    if (vars.get(name)) |v| return v;
    // OS fallback (POSIX getenv / Windows GetEnvironmentVariableW)
    return osEnv.OsEnv.get(name);
}

const BraceParse = struct {
    name: []const u8,
    op: ?[]const u8,
    arg: ?[]const u8,
};

fn parseBrace(inner: []const u8) BraceParse {
    // Name is first sequence of [A-Za-z_][A-Za-z0-9_]*
    var i: usize = 0;
    if (inner.len == 0) return .{ .name = inner, .op = null, .arg = null };
    if (!(std.ascii.isAlphabetic(inner[0]) or inner[0] == '_')) {
        // Invalid start, treat whole as name (will be missing)
        return .{ .name = inner, .op = null, .arg = null };
    }
    i = 1;
    while (i < inner.len and (std.ascii.isAlphanumeric(inner[i]) or inner[i] == '_')) : (i += 1) {}
    if (i >= inner.len) return .{ .name = inner, .op = null, .arg = null };
    const rest = inner[i..];
    if (rest.len >= 2 and rest[0] == ':' and (rest[1] == '-' or rest[1] == '+' or rest[1] == '?' or rest[1] == '=')) {
        return .{ .name = inner[0..i], .op = rest[0..2], .arg = rest[2..] };
    }
    if (rest.len >= 1 and (rest[0] == '-' or rest[0] == '+' or rest[0] == '?' or rest[0] == '=')) {
        return .{ .name = inner[0..i], .op = rest[0..1], .arg = rest[1..] };
    }
    // No recognized operator, treat whole as literal missing
    return .{ .name = inner, .op = null, .arg = null };
}

fn interpolateImpl(
    allocator: std.mem.Allocator,
    value: []const u8,
    vars: *const std.StringHashMap([]const u8),
    maxDepth: usize,
    currentDepth: usize,
    seenBuf: *[maxDepthLimit][]const u8,
    seenLen: *usize,
) (std.mem.Allocator.Error || error{ CircularDependency, MaxDepthExceeded })![]const u8 {
    if (currentDepth > maxDepth) return error.MaxDepthExceeded;

    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < value.len) {
        const startI = i;
        if (value[i] == '$' and i + 1 < value.len and value[i + 1] == '{') {
            const refStart = i + 2;
            var refEnd = refStart;
            // Handle nested ${} inside default values: find matching '}' with depth
            var pos = refStart;
            var found: ?usize = null;
            var innerDepth: usize = 0;
            while (pos < value.len) {
                if (value[pos] == '$' and pos + 1 < value.len and value[pos + 1] == '{') {
                    innerDepth += 1;
                    pos += 2;
                    continue;
                } else if (value[pos] == '}') {
                    if (innerDepth == 0) {
                        found = pos;
                        break;
                    } else {
                        innerDepth -= 1;
                    }
                }
                pos += 1;
            }
            if (found) |fe| {
                refEnd = fe;
                var inner = value[refStart..refEnd];
                // Strip $env: / $env. prefix (PowerShell style) for terminal env compat
                if (inner.len >= 4 and (std.mem.startsWith(u8, inner, "env:") or std.mem.startsWith(u8, inner, "env."))) {
                    inner = inner[4..];
                }
                i = refEnd + 1;
                const parsed = parseBrace(inner);

                // Circular check on the base name
                for (seenBuf.ptr[0..seenLen.*]) |s| {
                    if (std.mem.eql(u8, s, parsed.name)) return error.CircularDependency;
                }
                if (seenLen.* < maxDepthLimit) {
                    seenBuf.ptr[seenLen.*] = parsed.name;
                    seenLen.* += 1;
                }

                const maybeVal = lookupVar(parsed.name, vars);
                const isSet = maybeVal != null;
                const isNonempty = isSet and maybeVal.?.len != 0;

                var expanded: ?[]const u8 = null;
                var useDefault = false;
                var defaultArg: ?[]const u8 = null;
                var keepLiteral = false;

                if (parsed.op == null) {
                    if (maybeVal) |v| expanded = v else keepLiteral = true;
                } else if (std.mem.eql(u8, parsed.op.?, ":-")) {
                    if (isNonempty) expanded = maybeVal.? else {
                        useDefault = true;
                        defaultArg = parsed.arg orelse "";
                    }
                } else if (std.mem.eql(u8, parsed.op.?, "-")) {
                    if (isSet) expanded = maybeVal.? else {
                        useDefault = true;
                        defaultArg = parsed.arg orelse "";
                    }
                } else if (std.mem.eql(u8, parsed.op.?, ":+")) {
                    if (isNonempty) {
                        useDefault = true;
                        defaultArg = parsed.arg orelse "";
                    } else expanded = "";
                } else if (std.mem.eql(u8, parsed.op.?, "+")) {
                    if (isSet) {
                        useDefault = true;
                        defaultArg = parsed.arg orelse "";
                    } else expanded = "";
                } else if (std.mem.eql(u8, parsed.op.?, ":?") or std.mem.eql(u8, parsed.op.?, "?")) {
                    const needAlt = if (std.mem.eql(u8, parsed.op.?, ":?")) !isNonempty else !isSet;
                    if (!needAlt) expanded = maybeVal.? else {
                        if (parsed.arg) |a| {
                            // Expand error message as default (could also be considered error, but we return it)
                            useDefault = true;
                            defaultArg = a;
                        } else {
                            // No message, keep literal error? Return empty
                            useDefault = true;
                            defaultArg = "";
                        }
                    }
                } else if (std.mem.eql(u8, parsed.op.?, ":=") or std.mem.eql(u8, parsed.op.?, "=")) {
                    // := and = assign default if missing; we mimic :- behavior (no actual assign to map for now)
                    const needDefault = if (std.mem.eql(u8, parsed.op.?, ":=")) !isNonempty else !isSet;
                    if (!needDefault) expanded = maybeVal.? else {
                        useDefault = true;
                        defaultArg = parsed.arg orelse "";
                    }
                } else {
                    // Unknown operator, fallback to plain
                    if (maybeVal) |v| expanded = v else keepLiteral = true;
                }

                if (keepLiteral) {
                    try result.appendSlice(allocator, value[startI..i]);
                } else if (useDefault) {
                    const def = defaultArg orelse "";
                    // Recursively interpolate the default/alt string itself
                    const resolvedDef = try interpolateImpl(
                        allocator,
                        def,
                        vars,
                        maxDepth,
                        currentDepth + 1,
                        seenBuf,
                        seenLen,
                    );
                    defer allocator.free(resolvedDef);
                    try result.appendSlice(allocator, resolvedDef);
                } else if (expanded) |v| {
                    const resolved = try interpolateImpl(
                        allocator,
                        v,
                        vars,
                        maxDepth,
                        currentDepth + 1,
                        seenBuf,
                        seenLen,
                    );
                    defer if (resolved.ptr != v.ptr) allocator.free(resolved);
                    try result.appendSlice(allocator, resolved);
                }
            } else {
                try result.append(allocator, value[i]);
                i += 1;
            }
        } else if (value[i] == '$' and i + 5 < value.len and (std.mem.startsWith(u8, value[i + 1 ..], "env:") or std.mem.startsWith(u8, value[i + 1 ..], "env.")) and (value[i + 5] == '_' or std.ascii.isAlphabetic(value[i + 5]))) {
            // $env:VAR or $env.VAR (PowerShell style)
            const dollarPos = i;
            const varStart = i + 5;
            var varEnd = varStart;
            while (varEnd < value.len and (std.ascii.isAlphanumeric(value[varEnd]) or value[varEnd] == '_')) : (varEnd += 1) {}
            const refName = value[varStart..varEnd];
            i = varEnd;
            for (seenBuf.ptr[0..seenLen.*]) |s| {
                if (std.mem.eql(u8, s, refName)) return error.CircularDependency;
            }
            if (seenLen.* < maxDepthLimit) {
                seenBuf.ptr[seenLen.*] = refName;
                seenLen.* += 1;
            }
            if (lookupVar(refName, vars)) |refValue| {
                const resolved = try interpolateImpl(allocator, refValue, vars, maxDepth, currentDepth + 1, seenBuf, seenLen);
                defer if (resolved.ptr != refValue.ptr) allocator.free(resolved);
                try result.appendSlice(allocator, resolved);
            } else {
                try result.appendSlice(allocator, value[dollarPos..i]);
            }
        } else if (value[i] == '$' and i + 1 < value.len and (std.ascii.isAlphabetic(value[i + 1]) or value[i + 1] == '_')) {
            const dollarPos = i;
            const refStart = i + 1;
            var refEnd = refStart;
            while (refEnd < value.len and (std.ascii.isAlphanumeric(value[refEnd]) or value[refEnd] == '_')) {
                refEnd += 1;
            }
            const refName = value[refStart..refEnd];
            i = refEnd;

            for (seenBuf.ptr[0..seenLen.*]) |s| {
                if (std.mem.eql(u8, s, refName)) return error.CircularDependency;
            }

            if (seenLen.* < maxDepthLimit) {
                seenBuf.ptr[seenLen.*] = refName;
                seenLen.* += 1;
            }

            if (lookupVar(refName, vars)) |refValue| {
                const resolved = try interpolateImpl(
                    allocator,
                    refValue,
                    vars,
                    maxDepth,
                    currentDepth + 1,
                    seenBuf,
                    seenLen,
                );
                defer if (resolved.ptr != refValue.ptr)
                    allocator.free(resolved);
                try result.appendSlice(allocator, resolved);
            } else {
                try result.appendSlice(allocator, value[dollarPos..i]);
            }
        } else {
            try result.append(allocator, value[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Resolve all interpolations in a list of entries.
pub fn interpolateAll(
    allocator: std.mem.Allocator,
    entries: []struct { key: []const u8, value: []const u8 },
    maxDepth: usize,
) (std.mem.Allocator.Error || error{ CircularDependency, MaxDepthExceeded })!void {
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    for (entries) |entry| {
        _ = try vars.put(entry.key, entry.value);
    }

    for (entries) |*entry| {
        if (std.mem.indexOf(u8, entry.value, "${") != null or
            (entry.value.len > 0 and entry.value[0] == '$'))
        {
            var seenBuf: [maxDepthLimit][]const u8 = undefined;
            var seenLen: usize = 0;
            const resolved = interpolateImpl(
                allocator,
                entry.value,
                &vars,
                maxDepth,
                0,
                &seenBuf,
                &seenLen,
            ) catch continue;
            allocator.free(entry.value);
            entry.value = resolved;
        }
    }
}

test "interpolate basic" {
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("HOST", "localhost");
    _ = try vars.put("PORT", "8080");

    const result = try interpolate(
        std.testing.allocator,
        "http://${HOST}:${PORT}",
        &vars,
        10,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("http://localhost:8080", result);
}

test "interpolate missing var" {
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();

    const result = try interpolate(
        std.testing.allocator,
        "${MISSING}",
        &vars,
        10,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("${MISSING}", result);
}

test "interpolate circular dependency" {
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("A", "${B}");
    _ = try vars.put("B", "${A}");

    const result = interpolate(
        std.testing.allocator,
        "${A}",
        &vars,
        10,
    );
    try std.testing.expectError(error.CircularDependency, result);
}

test "interpolate max depth exceeded" {
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("A", "${B}");
    _ = try vars.put("B", "${A}");

    const result = interpolate(
        std.testing.allocator,
        "${A}",
        &vars,
        1,
    );
    try std.testing.expectError(error.MaxDepthExceeded, result);
}

test "interpolate default value :-" {
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("EMPTY", "");
    const r1 = try interpolate(std.testing.allocator, "${MISSING:-fallback}", &vars, 10);
    defer std.testing.allocator.free(r1);
    try std.testing.expectEqualStrings("fallback", r1);
    const r2 = try interpolate(std.testing.allocator, "${EMPTY:-fallback}", &vars, 10);
    defer std.testing.allocator.free(r2);
    try std.testing.expectEqualStrings("fallback", r2);
    const r3 = try interpolate(std.testing.allocator, "${EMPTY-fallback}", &vars, 10);
    defer std.testing.allocator.free(r3);
    try std.testing.expectEqualStrings("", r3);
}

test "interpolate alt value :+" {
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("SET", "yes");
    _ = try vars.put("EMPTY", "");
    const r1 = try interpolate(std.testing.allocator, "${SET:+alt}", &vars, 10);
    defer std.testing.allocator.free(r1);
    try std.testing.expectEqualStrings("alt", r1);
    const r2 = try interpolate(std.testing.allocator, "${EMPTY:+alt}", &vars, 10);
    defer std.testing.allocator.free(r2);
    try std.testing.expectEqualStrings("", r2);
    const r3 = try interpolate(std.testing.allocator, "${MISSING:+alt}", &vars, 10);
    defer std.testing.allocator.free(r3);
    try std.testing.expectEqualStrings("", r3);
}

test "interpolate os fallback" {
    const os = @import("os_env.zig");
    try os.OsEnv.set("ENV_ZIG_INTERP_OS_FALLBACK_TEST", "from_os");
    defer os.OsEnv.unset("ENV_ZIG_INTERP_OS_FALLBACK_TEST") catch {};
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    const r = try interpolate(std.testing.allocator, "${ENV_ZIG_INTERP_OS_FALLBACK_TEST}", &vars, 10);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("from_os", r);
}

test "interpolate nested default" {
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    _ = try vars.put("INNER", "inner_val");
    const r = try interpolate(std.testing.allocator, "${MISSING:-${INNER}}", &vars, 10);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("inner_val", r);
}

test "interpolate $env prefix" {
    const os = @import("os_env.zig");
    try os.OsEnv.set("ENV_ZIG_ENV_PREFIX_TEST", "env_val");
    defer os.OsEnv.unset("ENV_ZIG_ENV_PREFIX_TEST") catch {};
    var vars = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer vars.deinit();
    const r1 = try interpolate(std.testing.allocator, "${env:ENV_ZIG_ENV_PREFIX_TEST}", &vars, 10);
    defer std.testing.allocator.free(r1);
    try std.testing.expectEqualStrings("env_val", r1);
    const r2 = try interpolate(std.testing.allocator, "$env:ENV_ZIG_ENV_PREFIX_TEST", &vars, 10);
    defer std.testing.allocator.free(r2);
    try std.testing.expectEqualStrings("env_val", r2);
    const r3 = try interpolate(std.testing.allocator, "${env.ENV_ZIG_ENV_PREFIX_TEST:-fallback}", &vars, 10);
    defer std.testing.allocator.free(r3);
    try std.testing.expectEqualStrings("env_val", r3);
}
