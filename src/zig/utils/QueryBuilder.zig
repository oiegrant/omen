const std = @import("std");

pub const QueryBuilder = struct {
    allocator: std.mem.Allocator,
    params: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) QueryBuilder {
        return .{
            .allocator = allocator,
            .params = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *QueryBuilder) void {
        var it = self.params.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.params.deinit();
    }

    pub fn addString(self: *QueryBuilder, key: []const u8, value: []const u8) !void {
        if (self.params.get(key)) |old_value| {
            self.allocator.free(old_value);
        }
        const owned_value = try self.allocator.dupe(u8, value);
        try self.params.put(key, owned_value);
    }

    pub fn addInt(self: *QueryBuilder, key: []const u8, value: anytype) !void {
        if (self.params.get(key)) |old_value| {
            self.allocator.free(old_value);
        }

        const str = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
        try self.params.put(key, str);
    }

    pub fn addBool(self: *QueryBuilder, key: []const u8, value: bool) !void {
        if (self.params.get(key)) |old_value| {
            self.allocator.free(old_value);
        }
        const str = try self.allocator.dupe(u8, if (value) "true" else "false");
        try self.params.put(key, str);
    }

    pub fn remove(self: *QueryBuilder, key: []const u8) !void {
        if (self.params.fetchRemove(key)) |kv| {
            self.allocator.free(kv.value);
        }
    }

    pub fn clear(self: *QueryBuilder) void {
        var it = self.params.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.params.clearRetainingCapacity();
    }

    pub fn toUrl(self: *const QueryBuilder, base_url: []const u8) ![]u8 {
        var url = try std.ArrayList(u8).initCapacity(self.allocator, base_url.len);
        errdefer url.deinit(self.allocator);

        try url.appendSlice(self.allocator, base_url);

        var first = true;
        var it = self.params.iterator();
        while (it.next()) |entry| {
            try url.appendSlice(self.allocator, if (first) "?" else "&");
            try url.appendSlice(self.allocator, entry.key_ptr.*);
            try url.append(self.allocator, '=');
            try url.appendSlice(self.allocator, entry.value_ptr.*);
            first = false;
        }

        return url.toOwnedSlice(self.allocator);
    }
};

// Usage:
// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const allocator = gpa.allocator();

//     var builder = QueryBuilder.init(allocator);
//     defer builder.deinit();

//     // Chainable builder pattern
//     try builder.addInt("limit", 100);
//     try builder.addInt("offset", 0);
//     try builder.addString("order", "id");
//     try builder.addBool("ascending", false);
//     try builder.addBool("closed", false);
//     try builder.addBool("active", true);

//     const url1 = try builder.toUrl("https://api.example.com/markets");
//     defer allocator.free(url1);
//     std.debug.print("URL: {s}\n", .{url1});

//     // Increment offset
//     const current_offset = try std.fmt.parseInt(u32, builder.params.get("offset").?, 10);
//     const limit = try std.fmt.parseInt(u32, builder.params.get("limit").?, 10);
//     try builder.addInt("offset", current_offset + limit);

//     const url2 = try builder.toUrl("https://api.example.com/markets");
//     defer allocator.free(url2);
//     std.debug.print("Next page: {s}\n", .{url2});

//     // Remove a param
//     try builder.remove("closed");

//     const url3 = try builder.toUrl("https://api.example.com/markets");
//     defer allocator.free(url3);
//     std.debug.print("Without closed: {s}\n", .{url3});
// }
