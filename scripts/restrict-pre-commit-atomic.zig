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
/// 4. Executes the command using execv
/// 5. Terminates the process (execv replaces current process)
///
/// # Errors
/// Returns error if:
/// - The operating system is not supported
/// - The execv call fails
pub fn main() !void {
    // Use page allocator for command argument construction
    const allocator = std.heap.page_allocator;

    // Extract the command name from the executable filename
    const executable_path = std.process.getExecutablePath() catch {
        std.log.err("Failed to get executable path", .{});
        return error.ExecutablePathError;
    };

    // Extract the filename from the path
    const filename = std.mem.lastIndexOf(u8, executable_path, '/') orelse {
        std.log.err("Failed to extract filename", .{});
        return error.FilenameExtractionError;
    } + 1;

    // Extract the filename without the extension
    const filename_without_extension = std.mem.lastIndexOf(u8, filename, '.') orelse {
        std.log.err("Failed to extract filename without extension", .{});
        return error.ExtensionExtractionError;
    };

    const command_name = filename[0..filename_without_extension];

    // Determine the appropriate command based on the operating system
    const command_prefix = determine_os_specific_command(command_name);

    // Get command line arguments (excluding the program name)
    const arguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, arguments);

    // Allocate memory for the complete command argument vector
    var argv = try allocator.alloc([]const u8, command_prefix.len + arguments.len - 1);
    defer allocator.free(argv);

    // Construct the complete command by combining prefix and arguments
    @memcpy(argv[0..command_prefix.len], command_prefix);
    @memcpy(argv[command_prefix.len..], arguments[1..]);

    // Execute the command, replacing the current process
    // This call will only return if there's an error
    // Note: execv is not supported on Windows, so we use a different approach
    if (builtin.os.tag == .windows) {
        // For Windows, we need to use CreateProcess or similar
        // This is a simplified version - in a real implementation, you would
        // need to properly handle the Windows process creation API
        std.log.err("Windows process execution not implemented in this version", .{});
        std.process.exit(1);
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
///
/// # Parameters
/// - command_name: The name of the command to execute
///
/// # Returns
/// - Array of command and arguments for the current OS
/// - For unsupported OS, this function will exit the process
fn determine_os_specific_command(command_name: []const u8) []const []const u8 {
    // Allocate memory for the script filename
    const ps1_filename = std.heap.page_allocator.alloc(u8, command_name.len + 4) catch {
        std.log.err("Memory allocation failed", .{});
        std.process.exit(1);
    };
    const bash_filename = std.heap.page_allocator.alloc(u8, command_name.len + 5) catch {
        std.heap.page_allocator.free(ps1_filename);
        std.log.err("Memory allocation failed", .{});
        std.process.exit(1);
    };
    const sh_filename = std.heap.page_allocator.alloc(u8, command_name.len + 3) catch {
        std.heap.page_allocator.free(ps1_filename);
        std.heap.page_allocator.free(bash_filename);
        std.log.err("Memory allocation failed", .{});
        std.process.exit(1);
    };

    // Copy the command name and add extensions
    @memcpy(ps1_filename[0..command_name.len], command_name);
    @memcpy(ps1_filename[command_name.len .. command_name.len + 4], ".ps1");

    @memcpy(bash_filename[0..command_name.len], command_name);
    @memcpy(bash_filename[command_name.len .. command_name.len + 5], ".bash");

    @memcpy(sh_filename[0..command_name.len], command_name);
    @memcpy(sh_filename[command_name.len .. command_name.len + 3], ".sh");

    return switch (builtin.os.tag) {
        .windows => &[_][]const u8{
            "pwsh",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            ps1_filename,
        },
        .linux => &[_][]const u8{
            "bash",
            bash_filename,
        },
        .macos => &[_][]const u8{
            "sh",
            sh_filename,
        },
        else => {
            std.heap.page_allocator.free(ps1_filename);
            std.heap.page_allocator.free(bash_filename);
            std.heap.page_allocator.free(sh_filename);
            std.log.err("Unsupported operating system detected", .{});
            std.process.exit(1);
            unreachable;
        },
    };
}
