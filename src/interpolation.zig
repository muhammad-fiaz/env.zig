const std = @import("std");
const os_env = @import("os_env.zig");

/// Maximum number of interpolation references tracked for cycle detection.
const max_depth_limit = 64;

/// Resolve variable interpolation in a value string.
/// Replaces ${VAR}, ${VAR:-default}, ${VAR:+alt}, $VAR with values from map or OS env.
/// OS fallback: if not found in vars, checks process environment (cross-platform).
pub fn interpolate(
    allocator: std.mem.Allocator,
    value: []const u8,
    vars: *const std.StringHashMap([]const u8),
    max_depth: usize,
) (std.mem.Allocator.Error || error{ CircularDependency, MaxDepthExceeded })![]const u8 {
    var seen_buf: [max_depth_limit][]const u8 = undefined;
    var seen_len: usize = 0;
    return interpolateImpl(allocator, value, vars, max_depth, 0, &seen_buf, &seen_len);
}

fn lookupVar(name: []const u8, vars: *const std.StringHashMap([]const u8)) ?[]const u8 {
    if (vars.get(name)) |v| return v;
    // OS fallback (POSIX getenv / Windows GetEnvironmentVariableW)
    return os_env.OsEnv.get(name);
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
    max_depth: usize,
    current_depth: usize,
    seen_buf: *[max_depth_limit][]const u8,
    seen_len: *usize,
) (std.mem.Allocator.Error || error{ CircularDependency, MaxDepthExceeded })![]const u8 {
    if (current_depth > max_depth) return error.MaxDepthExceeded;

    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < value.len) {
        const start_i = i;
        if (value[i] == '$' and i + 1 < value.len and value[i + 1] == '{') {
            const ref_start = i + 2;
            var ref_end = ref_start;
            // Handle nested ${} inside default values: find matching '}' with depth
            var pos = ref_start;
            var found: ?usize = null;
            var inner_depth: usize = 0;
            while (pos < value.len) {
                if (value[pos] == '$' and pos + 1 < value.len and value[pos + 1] == '{') {
                    inner_depth += 1;
                    pos += 2;
                    continue;
                } else if (value[pos] == '}') {
                    if (inner_depth == 0) {
                        found = pos;
                        break;
                    } else {
                        inner_depth -= 1;
                    }
                }
                pos += 1;
            }
            if (found) |fe| {
                ref_end = fe;
                var inner = value[ref_start..ref_end];
                // Strip $env: / $env. prefix (PowerShell style) for terminal env compat
                if (inner.len >= 4 and (std.mem.startsWith(u8, inner, "env:") or std.mem.startsWith(u8, inner, "env."))) {
                    inner = inner[4..];
                }
                i = ref_end + 1;
                const parsed = parseBrace(inner);

                // Circular check on the base name
                for (seen_buf.ptr[0..seen_len.*]) |s| {
                    if (std.mem.eql(u8, s, parsed.name)) return error.CircularDependency;
                }
                if (seen_len.* < max_depth_limit) {
                    seen_buf.ptr[seen_len.*] = parsed.name;
                    seen_len.* += 1;
                }

                const maybe_val = lookupVar(parsed.name, vars);
                const is_set = maybe_val != null;
                const is_nonempty = is_set and maybe_val.?.len != 0;

                var expanded: ?[]const u8 = null;
                var use_default = false;
                var default_arg: ?[]const u8 = null;
                var keep_literal = false;

                if (parsed.op == null) {
                    if (maybe_val) |v| expanded = v else keep_literal = true;
                } else if (std.mem.eql(u8, parsed.op.?, ":-")) {
                    if (is_nonempty) expanded = maybe_val.? else {
                        use_default = true;
                        default_arg = parsed.arg orelse "";
                    }
                } else if (std.mem.eql(u8, parsed.op.?, "-")) {
                    if (is_set) expanded = maybe_val.? else {
                        use_default = true;
                        default_arg = parsed.arg orelse "";
                    }
                } else if (std.mem.eql(u8, parsed.op.?, ":+")) {
                    if (is_nonempty) {
                        use_default = true;
                        default_arg = parsed.arg orelse "";
                    } else expanded = "";
                } else if (std.mem.eql(u8, parsed.op.?, "+")) {
                    if (is_set) {
                        use_default = true;
                        default_arg = parsed.arg orelse "";
                    } else expanded = "";
                } else if (std.mem.eql(u8, parsed.op.?, ":?") or std.mem.eql(u8, parsed.op.?, "?")) {
                    const need_alt = if (std.mem.eql(u8, parsed.op.?, ":?")) !is_nonempty else !is_set;
                    if (!need_alt) expanded = maybe_val.? else {
                        if (parsed.arg) |a| {
                            // Expand error message as default (could also be considered error, but we return it)
                            use_default = true;
                            default_arg = a;
                        } else {
                            // No message, keep literal error? Return empty
                            use_default = true;
                            default_arg = "";
                        }
                    }
                } else if (std.mem.eql(u8, parsed.op.?, ":=") or std.mem.eql(u8, parsed.op.?, "=")) {
                    // := and = assign default if missing; we mimic :- behavior (no actual assign to map for now)
                    const need_default = if (std.mem.eql(u8, parsed.op.?, ":=")) !is_nonempty else !is_set;
                    if (!need_default) expanded = maybe_val.? else {
                        use_default = true;
                        default_arg = parsed.arg orelse "";
                    }
                } else {
                    // Unknown operator, fallback to plain
                    if (maybe_val) |v| expanded = v else keep_literal = true;
                }

                if (keep_literal) {
                    try result.appendSlice(allocator, value[start_i..i]);
                } else if (use_default) {
                    const def = default_arg orelse "";
                    // Recursively interpolate the default/alt string itself
                    const resolved_def = try interpolateImpl(
                        allocator,
                        def,
                        vars,
                        max_depth,
                        current_depth + 1,
                        seen_buf,
                        seen_len,
                    );
                    defer allocator.free(resolved_def);
                    try result.appendSlice(allocator, resolved_def);
                } else if (expanded) |v| {
                    const resolved = try interpolateImpl(
                        allocator,
                        v,
                        vars,
                        max_depth,
                        current_depth + 1,
                        seen_buf,
                        seen_len,
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
            const dollar_pos = i;
            const var_start = i + 5;
            var var_end = var_start;
            while (var_end < value.len and (std.ascii.isAlphanumeric(value[var_end]) or value[var_end] == '_')) : (var_end += 1) {}
            const ref_name = value[var_start..var_end];
            i = var_end;
            for (seen_buf.ptr[0..seen_len.*]) |s| {
                if (std.mem.eql(u8, s, ref_name)) return error.CircularDependency;
            }
            if (seen_len.* < max_depth_limit) {
                seen_buf.ptr[seen_len.*] = ref_name;
                seen_len.* += 1;
            }
            if (lookupVar(ref_name, vars)) |ref_value| {
                const resolved = try interpolateImpl(allocator, ref_value, vars, max_depth, current_depth + 1, seen_buf, seen_len);
                defer if (resolved.ptr != ref_value.ptr) allocator.free(resolved);
                try result.appendSlice(allocator, resolved);
            } else {
                try result.appendSlice(allocator, value[dollar_pos..i]);
            }
        } else if (value[i] == '$' and i + 1 < value.len and (std.ascii.isAlphabetic(value[i + 1]) or value[i + 1] == '_')) {
            const dollar_pos = i;
            const ref_start = i + 1;
            var ref_end = ref_start;
            while (ref_end < value.len and (std.ascii.isAlphanumeric(value[ref_end]) or value[ref_end] == '_')) {
                ref_end += 1;
            }
            const ref_name = value[ref_start..ref_end];
            i = ref_end;

            for (seen_buf.ptr[0..seen_len.*]) |s| {
                if (std.mem.eql(u8, s, ref_name)) return error.CircularDependency;
            }

            if (seen_len.* < max_depth_limit) {
                seen_buf.ptr[seen_len.*] = ref_name;
                seen_len.* += 1;
            }

            if (lookupVar(ref_name, vars)) |ref_value| {
                const resolved = try interpolateImpl(
                    allocator,
                    ref_value,
                    vars,
                    max_depth,
                    current_depth + 1,
                    seen_buf,
                    seen_len,
                );
                defer if (resolved.ptr != ref_value.ptr)
                    allocator.free(resolved);
                try result.appendSlice(allocator, resolved);
            } else {
                try result.appendSlice(allocator, value[dollar_pos..i]);
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
    max_depth: usize,
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
            var seen_buf: [max_depth_limit][]const u8 = undefined;
            var seen_len: usize = 0;
            const resolved = interpolateImpl(
                allocator,
                entry.value,
                &vars,
                max_depth,
                0,
                &seen_buf,
                &seen_len,
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
