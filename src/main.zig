const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Interpreter = @import("interpreter.zig").Interpreter;
const repl = @import("repl.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    // Get command-line arguments
    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();

    // Skip the program name
    _ = arg_iterator.next();

    // Check if we have any arguments
    const filename = arg_iterator.next();
    if (filename == null) {
        // Start REPL
        try repl.startREPL(&allocator);
        return;
    }

    // Check file extension
    if (!std.mem.endsWith(u8, filename.?, ".mer")) {
        std.debug.print("Error: File must have .mer extension\n", .{});
        std.process.exit(1);
        return;
    }

    // Open and read the file
    var file = try std.fs.cwd().openFile(filename.?, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, @intCast(file_size));
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    // Convert buffer to string slice
    const source_code = buffer;

    // Initialize the interpreter once
    var interpreter = Interpreter.init(&allocator);

    // Initialize the lexer for the entire source code
    var lexer = Lexer.init(source_code);

    // Initialize the parser
    var parser = Parser.init(&lexer, &allocator);

    // Parse and evaluate until we reach the end of the file
    while (true) {
        const ast = parser.parseStatement() catch |err| {
            if (err == error.EndOfFile) break;
            if (err == error.UnexpectedToken) {
                // Check if we're at the end of input with only whitespace/semicolons remaining
                const token = lexer.peek();
                if (token == .EOF) break;  // Exit if we're at EOF
                if (token == .Semicolon) {
                    _ = lexer.nextToken();  // consume the semicolon
                    continue;  // Skip this iteration and continue parsing
                }
                std.debug.print("Unexpected token encountered\n", .{});
                return err;
            }
            return err;
        };
        const result = try interpreter.evaluate(ast);

        if (interpreter.shouldPrintResult(source_code)) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print("{d}\n", .{result});
        }
    }
}