pub const CanonicalDBConfig = struct {
    pool_size: u8,
    port: u16,
    host: []const u8,
    username: []const u8,
    password: []const u8,
    database: []const u8,
    timeout: u32,
};
