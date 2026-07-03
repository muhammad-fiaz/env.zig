const std = @import("std");

/// Maximum number of interpolation references tracked for cycle detection.
const max_depth_limit = 64;

/// Resolve variable interpolation in a value string.
/// Replaces ${VAR} and $VAR references with their values from the provided map.
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
            while (ref_end < value.len and value[ref_end] != '}') {
                ref_end += 1;
            }
            if (ref_end < value.len) {
                const ref_name = value[ref_start..ref_end];
                i = ref_end + 1;

                for (seen_buf.ptr[0..seen_len.*]) |s| {
                    if (std.mem.eql(u8, s, ref_name)) return error.CircularDependency;
                }

                if (seen_len.* < max_depth_limit) {
                    seen_buf.ptr[seen_len.*] = ref_name;
                    seen_len.* += 1;
                }

                if (vars.get(ref_name)) |ref_value| {
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
                    try result.appendSlice(allocator, value[start_i..i]);
                }
            } else {
                try result.append(allocator, value[i]);
                i += 1;
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

            if (vars.get(ref_name)) |ref_value| {
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
