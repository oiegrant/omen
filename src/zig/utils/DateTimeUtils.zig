const std = @import("std");

// Helper: Parse ISO 8601 date string to Unix timestamp in milliseconds
pub fn ISO_8601_UTC_To_TimestampMs(date_str: []const u8) !i64 {
    if (date_str.len == 0) return 0;

    // Expected format: "2025-12-31T12:00:00Z" (20 characters minimum)
    if (date_str.len < 20) return error.InvalidDateFormat;

    // Verify separators
    if (date_str[4] != '-' or date_str[7] != '-' or
        date_str[10] != 'T' or date_str[13] != ':' or
        date_str[16] != ':')
    {
        return error.InvalidDateFormat;
    }

    // Parse components
    const year = try std.fmt.parseInt(i32, date_str[0..4], 10);
    const month = try std.fmt.parseInt(u8, date_str[5..7], 10);
    const day = try std.fmt.parseInt(u8, date_str[8..10], 10);
    const hour = try std.fmt.parseInt(u8, date_str[11..13], 10);
    const minute = try std.fmt.parseInt(u8, date_str[14..16], 10);
    const second = try std.fmt.parseInt(u8, date_str[17..19], 10);

    // Validate ranges
    if (month < 1 or month > 12) return error.InvalidMonth;
    if (day < 1 or day > 31) return error.InvalidDay;
    if (hour > 23) return error.InvalidHour;
    if (minute > 59) return error.InvalidMinute;
    if (second > 59) return error.InvalidSecond;

    // Calculate Unix timestamp in seconds
    const days = daysSinceEpoch(year, month, day);
    const seconds: i64 = days * 86400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);

    // Convert to milliseconds
    return seconds * 1000;
}

fn isLeapYear(year: i32) bool {
    return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
}

fn daysSinceEpoch(year: i32, month: u8, day: u8) i64 {
    // Days in each month (non-leap year)
    const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    var days: i64 = 0;

    // Add days for complete years since 1970
    var y: i32 = 1970;
    while (y < year) : (y += 1) {
        days += if (isLeapYear(y)) 366 else 365;
    }

    // Add days for complete months in current year
    var m: usize = 1;
    while (m < month) : (m += 1) {
        days += days_in_month[m - 1];
        // Add leap day if February in leap year
        if (m == 2 and isLeapYear(year)) {
            days += 1;
        }
    }

    // Add remaining days (subtract 1 because day 1 = 0 days elapsed)
    days += day - 1;

    return days;
}

// Test the implementation
// pub fn main() !void {
//     const test_dates = [_][]const u8{
//         "2025-12-31T12:00:00Z",
//         "1970-01-01T00:00:00Z", // Epoch
//         "2024-02-29T23:59:59Z", // Leap year
//         "2000-01-01T00:00:00Z",
//     };

//     for (test_dates) |date| {
//         const timestamp = try parseDateToTimestamp(date);
//         std.debug.print("{s} -> {} ms\n", .{ date, timestamp });
//     }
// }
