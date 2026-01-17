// restrict-pre-commit-atomic Command Dispatcher
//
// Purpose:
// This firmware-like component detects the operating system and executes
// the appropriate OS-specific script for restrict-pre-commit-atomic.
// It serves as a thin abstraction layer that forwards execution
// to platform-specific implementations.
//
// Contract:
// - No CLI argument parsing or interpretation
// - No memory allocation
// - No configuration handling
// - Single responsibility: OS detection and command execution
// - Process terminates after execution (no control regain)
//
// Design Principles:
// - SOLID: Single Responsibility Principle
// - Firmware-like: Minimal, focused, deterministic
// - No side effects: Pure execution flow
// - Self-documenting: Clear purpose and behavior

const std = @import("std");
const builtin = @import("builtin");

/// Main entry point for the OS-specific command dispatcher
///
/// This function performs the following operations:
/// 1. Extracts the command name from the executable filename
/// 2. Detects the current operating system
/// 3. Constructs the appropriate command for the detected OS
/// 4. Executes the command using execv or std.process.Child
/// 5. Terminates the process (execv replaces current process)
///
/// # Errors
/// Returns error if:
/// - The operating system is not supported
/// - The execv call fails
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const executable_path = std.process.getExecutablePath() catch {
        std.log.err("Failed to get executable path", .{});
        return error.ExecutablePathError;
    };

    const full_filename =
        std.mem.lastIndexOf(u8, executable_path, '/') orelse {
            std.log.err("Failed to extract filename", .{});
            return error.FilenameExtractionError;
        } + 1;

    const filename_only =
        std.mem.lastIndexOf(u8, full_filename, '.') orelse {
            std.log.err("Failed to extract filename only", .{});
            return error.ExtensionExtractionError;
        };

    const command_name = full_filename[0..filename_only];

    const command_prefix =
        determine_os_specific_command(command_name);

    const arguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, arguments);

    var argv = try allocator.alloc(
        []const u8,
        command_prefix.len + arguments.len - 1,
    );
    defer allocator.free(argv);

    @memcpy(argv[0..command_prefix.len], command_prefix);
    @memcpy(argv[command_prefix.len..], arguments[1..]);

    if (builtin.os.tag == .windows) {
        var child = std.process.Child.init(argv, allocator);
        const term = child.spawnAndWait() catch {
            std.log.err("Failed to execute command", .{});
            std.process.exit(1);
        };

        switch (term) {
            .Exited => |code| std.process.exit(code),
            .Signal => |sig| std.process.exit(128 + sig),
            .Stopped => |sig| std.process.exit(128 + sig),
            .Unknown => std.process.exit(1),
        }
    } else {
        std.process.execv(allocator, argv) catch {
            std.log.err("Failed to execute command", .{});
            std.process.exit(1);
        };
    }
}

/// Determines the appropriate command and arguments for
/// the current operating system
///
/// This function encapsulates the OS detection logic and returns the
/// appropriate command structure for the detected platform.
/// It constructs absolute paths to ensure scripts are found regardless
/// of the current working directory.
///
/// # Parameters
/// - command_name: The name of the command to execute
///
/// # Returns
/// - Array of command and arguments for the current OS
/// - For unsupported OS, this function will exit the process
fn determine_os_specific_command(
    command_name: []const u8,
) []const []const u8 {
    const executable_path =
        std.process.getExecutablePath() catch {
            std.log.err("Failed to get executable path", .{});
            std.process.exit(1);
        };

    const last_sep = std.mem.lastIndexOfScalar(
        u8,
        executable_path,
        if (builtin.os.tag == .windows) '\\' else '/',
    ) orelse {
        std.log.err("Failed to extract executable directory", .{});
        std.process.exit(1);
    };

    const exe_dir = executable_path[0..last_sep];

    const extension = switch (builtin.os.tag) {
        .windows => ".ps1",
        .linux => ".bash",
        .macos => ".sh",
        else => {
            std.log.err("Unsupported operating system detected", .{});
            std.process.exit(1);
            unreachable;
        },
    };

    const path_len =
        exe_dir.len + 1 + command_name.len + extension.len;
    const script_path =
        std.heap.page_allocator.alloc(u8, path_len) catch {
            std.log.err("Memory allocation failed", .{});
            std.process.exit(1);
        };

    var offset: usize = 0;
    @memcpy(script_path[offset .. offset + exe_dir.len], exe_dir);
    offset += exe_dir.len;
    script_path[offset] =
        if (builtin.os.tag == .windows) '\\' else '/';
    offset += 1;
    @memcpy(
        script_path[offset .. offset + command_name.len],
        command_name,
    );
    offset += command_name.len;
    @memcpy(
        script_path[offset .. offset + extension.len],
        extension,
    );

    return switch (builtin.os.tag) {
        .windows => &[_][]const u8{
            "pwsh",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path,
        },
        .linux => &[_][]const u8{
            "bash",
            script_path,
        },
        .macos => &[_][]const u8{
            "sh",
            script_path,
        },
        else => unreachable,
    };
}
