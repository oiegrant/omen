const std = @import("std");
const print = std.debug.print;
const time = std.time;
const Mutex = std.Thread.Mutex;

/// Snowflake ID Generator
///
/// Generates distributed unique 64-bit IDs with the following structure:
/// - 1 bit: unused (always 0)
/// - 41 bits: timestamp in milliseconds since custom epoch
/// - 10 bits: worker ID (5 bits datacenter + 5 bits worker)
/// - 12 bits: sequence number
pub const Snowflake = struct {
    /// Custom epoch (January 1, 2020 00:00:00 UTC)
    /// You can adjust this to your application's start date
    const EPOCH: i64 = 1577836800000;

    const TIMESTAMP_BITS: u6 = 41;
    const DATACENTER_BITS: u6 = 5;
    const WORKER_BITS: u6 = 5;
    const SEQUENCE_BITS: u6 = 12;

    const MAX_DATACENTER_ID: u16 = (1 << DATACENTER_BITS) - 1; // 31
    const MAX_WORKER_ID: u16 = (1 << WORKER_BITS) - 1; // 31
    const MAX_SEQUENCE: u16 = (1 << SEQUENCE_BITS) - 1; // 4095

    const WORKER_SHIFT: u6 = SEQUENCE_BITS;
    const DATACENTER_SHIFT: u6 = SEQUENCE_BITS + WORKER_BITS;
    const TIMESTAMP_SHIFT: u6 = SEQUENCE_BITS + WORKER_BITS + DATACENTER_BITS;

    datacenter_id: u16,
    worker_id: u16,
    sequence: u16,
    last_timestamp: i64,
    mutex: Mutex,

    pub const Error = error{
        ClockMovedBackwards,
        InvalidDatacenterId,
        InvalidWorkerId,
    };

    /// Initialize a new Snowflake ID generator
    pub fn init(datacenter_id: u16, worker_id: u16) Error!Snowflake {
        if (datacenter_id > MAX_DATACENTER_ID) {
            return Error.InvalidDatacenterId;
        }
        if (worker_id > MAX_WORKER_ID) {
            return Error.InvalidWorkerId;
        }

        return Snowflake{
            .datacenter_id = datacenter_id,
            .worker_id = worker_id,
            .sequence = 0,
            .last_timestamp = -1,
            .mutex = Mutex{},
        };
    }

    /// Generate a new unique ID
    pub fn nextId(self: *Snowflake) Error!u64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var timestamp = currentTimestamp();

        // Check for clock moving backwards
        if (timestamp < self.last_timestamp) {
            return Error.ClockMovedBackwards;
        }

        // Same millisecond - increment sequence
        if (timestamp == self.last_timestamp) {
            self.sequence = (self.sequence + 1) & MAX_SEQUENCE;

            // Sequence overflow - wait for next millisecond
            if (self.sequence == 0) {
                timestamp = waitNextMillis(self.last_timestamp);
            }
        } else {
            // New millisecond - reset sequence
            self.sequence = 0;
        }

        self.last_timestamp = timestamp;

        // Construct the ID
        const id: u64 =
            (@as(u64, @intCast(timestamp - EPOCH)) << TIMESTAMP_SHIFT) |
            (@as(u64, self.datacenter_id) << DATACENTER_SHIFT) |
            (@as(u64, self.worker_id) << WORKER_SHIFT) |
            @as(u64, self.sequence);

        return id;
    }

    /// Get current timestamp in milliseconds
    fn currentTimestamp() i64 {
        return time.milliTimestamp();
    }

    /// Wait until next millisecond
    fn waitNextMillis(last_timestamp: i64) i64 {
        var timestamp = currentTimestamp();
        while (timestamp <= last_timestamp) {
            timestamp = currentTimestamp();
        }
        return timestamp;
    }

    /// Parse a Snowflake ID into its components
    pub fn parse(id: u64) ParsedId {
        const timestamp = (id >> TIMESTAMP_SHIFT) + @as(u64, @intCast(EPOCH));
        const datacenter_id = (id >> DATACENTER_SHIFT) & MAX_DATACENTER_ID;
        const worker_id = (id >> WORKER_SHIFT) & MAX_WORKER_ID;
        const sequence = id & MAX_SEQUENCE;

        return ParsedId{
            .timestamp = @intCast(timestamp),
            .datacenter_id = @intCast(datacenter_id),
            .worker_id = @intCast(worker_id),
            .sequence = @intCast(sequence),
        };
    }
};

pub const ParsedId = struct {
    timestamp: i64,
    datacenter_id: u16,
    worker_id: u16,
    sequence: u16,
};

// Example usage and tests
pub fn main() !void {

    // Create a Snowflake generator
    var generator = try Snowflake.init(1, 1);

    print("Snowflake ID Generator Demo\n", .{});
    print("===========================\n\n", .{});

    // Generate some IDs
    print("Generating 10 IDs:\n", .{});
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const id = try generator.nextId();
        const parsed = Snowflake.parse(id);

        print("ID {d}: {d}\n", .{ i + 1, id });
        print("  Timestamp: {d} ms\n", .{parsed.timestamp});
        print("  Datacenter: {d}\n", .{parsed.datacenter_id});
        print("  Worker: {d}\n", .{parsed.worker_id});
        print("  Sequence: {d}\n\n", .{parsed.sequence});
    }

    // Benchmark
    print("\nBenchmark: Generating 100,000 IDs...\n", .{});
    const start = time.milliTimestamp();

    var count: usize = 0;
    while (count < 100_000) : (count += 1) {
        _ = try generator.nextId();
    }

    const end = time.milliTimestamp();
    const duration = end - start;

    print("Generated 100,000 IDs in {d} ms\n", .{duration});
    print("Rate: {d} IDs/second\n", .{@divTrunc(100_000 * 1000, duration)});
}

test "basic snowflake generation" {
    var generator = try Snowflake.init(1, 1);
    const id1 = try generator.nextId();
    const id2 = try generator.nextId();

    try std.testing.expect(id1 < id2);
}

test "parse snowflake id" {
    var generator = try Snowflake.init(5, 10);
    const id = try generator.nextId();
    const parsed = Snowflake.parse(id);

    try std.testing.expectEqual(@as(u16, 5), parsed.datacenter_id);
    try std.testing.expectEqual(@as(u16, 10), parsed.worker_id);
}

test "invalid datacenter id" {
    const result = Snowflake.init(32, 1);
    try std.testing.expectError(Snowflake.Error.InvalidDatacenterId, result);
}

test "invalid worker id" {
    const result = Snowflake.init(1, 32);
    try std.testing.expectError(Snowflake.Error.InvalidWorkerId, result);
}
