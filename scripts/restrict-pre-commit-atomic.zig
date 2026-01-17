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
// - Must use safe and secured handling of memory allocation,
//   such as page allocation
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
/// Execution flow:
/// 1. Extracts the command name from the executable filename
/// 2. Detects the current operating system
/// 3. Constructs the appropriate command for the detected OS
/// 4. Executes the command using execv (Unix) or std.process.Child (Windows)
/// 5. Terminates the process (execv replaces current process on Unix)
///
/// # Memory Management
/// All allocations use page_allocator with explicit defer statements for cleanup.
/// Memory is freed before process termination.
///
/// # Errors
/// Returns error if:
/// - Executable path cannot be determined
/// - Filename extraction fails (malformed path)
/// - Script path construction fails
/// - Operating system is not supported
/// - Command execution fails
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Retrieve the full path to this executable
    var exe_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const executable_path = std.fs.selfExePath(exe_path_buffer[0..]) catch {
        std.log.err("Failed to get executable path", .{});
        return error.ExecutablePathError;
    };

    // Determine the path separator for the current OS
    const sep = if (builtin.os.tag == .windows) '\\' else '/';

    // Extract the filename portion from the full executable path
    // Example: "/path/to/restrict-pre-commit-atomic" -> "restrict-pre-commit-atomic"
    const full_filename =
        std.mem.lastIndexOfScalar(u8, executable_path, sep) orelse {
            std.log.err("Failed to extract filename", .{});
            return error.FilenameExtractionError;
        } + 1;

    // Extract the command name without the file extension
    // Example: "restrict-pre-commit-atomic.exe" -> "restrict-pre-commit-atomic"
    // If no extension exists, use the entire filename
    const filename_slice = executable_path[full_filename..];
    const dot_index = std.mem.lastIndexOf(u8, filename_slice, ".") orelse filename_slice.len;
    const command_name = filename_slice[0..dot_index];

    // Capture all command-line arguments passed to this dispatcher
    const arguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, arguments);

    // Build the full path to the OS-specific script
    const script_path = build_script_path(allocator, executable_path, command_name) catch |err| {
        std.log.err("Failed to build script path: {}", .{err});
        return err;
    };
    defer allocator.free(script_path);

    const command_prefix = try determine_os_specific_command();

    // Construct the complete argv array: [interpreter, args..., script_path, original_args...]
    // Size: command_prefix + script_path + remaining arguments (skip argv[0])
    const argv_len = command_prefix.len + 1 + (arguments.len - 1);
    var argv = try allocator.alloc(
        []const u8,
        argv_len,
    );
    defer allocator.free(argv);

    @memcpy(argv[0..command_prefix.len], command_prefix);
    argv[command_prefix.len] = script_path;
    if (arguments.len > 1) {
        @memcpy(argv[command_prefix.len + 1 ..], arguments[1..]);
    }

    // Execute the script with the appropriate method for the OS
    if (builtin.os.tag == .windows) {
        // Windows: Use std.process.Child to spawn and wait for the process
        var child = std.process.Child.init(argv, allocator);
        const term = child.spawnAndWait() catch {
            std.log.err("Failed to execute command", .{});
            std.process.exit(1);
        };

        // Forward the exit code from the child process
        switch (term) {
            .Exited => |code| std.process.exit(code),
            .Signal => |sig| std.process.exit(@as(u8, @intCast(128 + sig))),
            .Stopped => |sig| std.process.exit(@as(u8, @intCast(128 + sig))),
            .Unknown => std.process.exit(1),
        }
    } else {
        // Unix-like systems: Use execv to replace the current process
        // This is more efficient as it doesn't spawn a child process
        std.process.execv(allocator, argv) catch {
            std.log.err("Failed to execute command", .{});
            std.process.exit(1);
        };
    }
    // Note: execv replaces the current process on Unix-like systems,
    // so execution never reaches this point on those platforms
}

/// Constructs the absolute path to the OS-specific script file
///
/// This function:
/// 1. Extracts the directory containing the executable
/// 2. Determines the appropriate script extension for the OS
/// 3. Allocates and constructs the full script path
///
/// Example paths constructed:
/// - Windows: "C:\path\to\restrict-pre-commit-atomic.ps1"
/// - Linux:   "/path/to/restrict-pre-commit-atomic.bash"
/// - macOS:   "/path/to/restrict-pre-commit-atomic.sh"
///
/// # Parameters
/// - allocator: Memory allocator for the path string (caller must free)
/// - executable_path: Full path to the current executable
/// - command_name: Name of the command without extension
///
/// # Returns
/// - Allocated string containing the full script path
/// - Caller is responsible for freeing the returned string
///
/// # Errors
/// - Returns error.DirectoryExtractionFailed if executable directory cannot be extracted
/// - Returns error.UnsupportedOperatingSystem if operating system is not supported
/// - Returns error.AllocationFailed if memory allocation fails
fn build_script_path(
    allocator: std.mem.Allocator,
    executable_path: []const u8,
    command_name: []const u8,
) ![]u8 {
    // Determine the path separator for the current OS
    const sep = if (builtin.os.tag == .windows) '\\' else '/';

    // Extract the directory portion of the executable path
    const last_sep = std.mem.lastIndexOfScalar(
        u8,
        executable_path,
        sep,
    ) orelse {
        std.log.err("Failed to extract executable directory", .{});
        return error.DirectoryExtractionFailed;
    };

    const exe_dir = executable_path[0..last_sep];

    // Determine the script extension based on the OS
    const extension = switch (builtin.os.tag) {
        .windows => ".ps1",
        .linux => ".bash",
        .macos => ".sh",
        else => {
            std.log.err("Unsupported operating system detected", .{});
            return error.UnsupportedOperatingSystem;
        },
    };

    // Calculate the total length needed for the path
    const path_len =
        exe_dir.len + 1 + command_name.len + extension.len;
    const script_path = allocator.alloc(u8, path_len) catch {
        std.log.err("Memory allocation failed", .{});
        return error.AllocationFailed;
    };

    // Construct the path by concatenating: directory + separator + command_name + extension
    var offset: usize = 0;
    @memcpy(script_path[offset .. offset + exe_dir.len], exe_dir);
    offset += exe_dir.len;
    script_path[offset] = sep;
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

    return script_path;
}

/// Determines the interpreter command and arguments for the current OS
///
/// Returns the appropriate shell interpreter and its configuration flags
/// needed to execute the OS-specific script. The script path is provided
/// separately by the caller and appended to this command.
///
/// Command structure by OS:
/// - Windows: ["pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
/// - Linux:   ["bash"]
/// - macOS:   ["sh"]
///
/// The script path is appended after these arguments by the caller.
///
/// # Returns
/// - Slice of strings containing the interpreter and its arguments
/// - Lifetime is static (compile-time constant)
fn determine_os_specific_command() ![]const []const u8 {
    return switch (builtin.os.tag) {
        .windows => &[_][]const u8{
            "pwsh", // PowerShell Core
            "-NoProfile", // Skip profile loading for faster startup
            "-ExecutionPolicy", // Allow script execution
            "Bypass", // Bypass execution policy for this invocation
            "-File", // Execute the following file
        },
        .linux => &[_][]const u8{
            "bash", // Bash shell
        },
        .macos => &[_][]const u8{
            "sh", // POSIX shell
        },
        else => {
            std.log.err("Unsupported operating system detected", .{});
            return error.UnsupportedOperatingSystem;
        },
    };
}
