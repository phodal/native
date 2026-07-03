//! Markup front-end for the declarative ui builder (design:
//! plans/zero-native/markup-authoring.md).
//!
//! This module owns the grammar: an HTML-like element tree with kebab-case
//! element and attribute names, `{binding}` expressions, `on-*` message
//! dispatch (`msg` or `msg:{arg}`), and `for`/`if`/`else` structure tags.
//! Parsing is type-agnostic; binding and message validation against a
//! concrete Model/Msg happens in the interpreter layer.
//!
//! The parser is deliberately strict: unknown syntax is an error with a
//! line/column position, never a silent skip — fast, specific failure is
//! the feedback loop markup authors (human or agent) rely on.

const std = @import("std");

pub const MarkupErrorInfo = struct {
    line: usize = 0,
    column: usize = 0,
    message: []const u8 = "",
};

pub const MarkupNodeKind = enum {
    element,
    text,
    for_block,
    if_block,
    else_block,
    template_block,
    use_block,
};

pub const MarkupAttr = struct {
    name: []const u8,
    value: []const u8,
    line: usize,
    column: usize,
};

pub const MarkupNode = struct {
    kind: MarkupNodeKind,
    /// Element name for `element` nodes ("row", "text-field", ...).
    name: []const u8 = "",
    attrs: []const MarkupAttr = &.{},
    children: []const MarkupNode = &.{},
    /// Raw text content (may contain `{...}` interpolations).
    text: []const u8 = "",
    line: usize = 0,
    column: usize = 0,

    pub fn attr(self: MarkupNode, name: []const u8) ?[]const u8 {
        for (self.attrs) |attribute| {
            if (std.mem.eql(u8, attribute.name, name)) return attribute.value;
        }
        return null;
    }
};

pub const MarkupDocument = struct {
    /// Top-level `<template name="..." args="...">` definitions, in file
    /// order. `<use>` sites reference them by name; a use may only
    /// reference templates defined earlier in the file (which also rules
    /// out recursion structurally).
    templates: []const MarkupNode = &.{},
    root: MarkupNode,

    pub fn templateIndex(self: MarkupDocument, name: []const u8) ?usize {
        for (self.templates, 0..) |template_node, index| {
            const template_name = template_node.attr("name") orelse continue;
            if (std.mem.eql(u8, template_name, name)) return index;
        }
        return null;
    }
};

/// Iterate a template's declared arg names (the space-separated `args`
/// attribute). Works at runtime and comptime.
pub fn templateArgs(template_node: MarkupNode) std.mem.TokenIterator(u8, .scalar) {
    return std.mem.tokenizeScalar(u8, template_node.attr("args") orelse "", ' ');
}

pub fn templateDeclaresArg(template_node: MarkupNode, name: []const u8) bool {
    var args = templateArgs(template_node);
    while (args.next()) |arg_name| {
        if (std.mem.eql(u8, arg_name, name)) return true;
    }
    return false;
}

pub const ParseError = error{ MarkupSyntax, OutOfMemory };

pub const Parser = struct {
    source: []const u8,
    index: usize = 0,
    line: usize = 1,
    column: usize = 1,
    arena: std.mem.Allocator,
    diagnostic: MarkupErrorInfo = .{},

    pub fn init(arena: std.mem.Allocator, source: []const u8) Parser {
        return .{ .arena = arena, .source = source };
    }

    /// Parse a document: comments and whitespace around zero or more
    /// top-level `<template>` definitions followed by exactly one root
    /// element.
    pub fn parse(self: *Parser) ParseError!MarkupDocument {
        var templates: std.ArrayListUnmanaged(MarkupNode) = .empty;
        while (true) {
            self.skipWhitespaceAndComments();
            if (self.index >= self.source.len and templates.items.len > 0) {
                return self.fail("expected a view root element after the template definitions");
            }
            const node = try self.parseElement();
            if (node.kind == .template_block) {
                try templates.append(self.arena, node);
                continue;
            }
            self.skipWhitespaceAndComments();
            if (self.index < self.source.len) {
                return self.fail("expected end of file after the root element");
            }
            return .{ .templates = templates.items, .root = node };
        }
    }

    fn parseElement(self: *Parser) ParseError!MarkupNode {
        const start_line = self.line;
        const start_column = self.column;
        if (!self.consumeByte('<')) return self.fail("expected '<' to open an element");
        const name = try self.parseName("element name");

        var attrs: std.ArrayListUnmanaged(MarkupAttr) = .empty;
        while (true) {
            self.skipWhitespace();
            const byte = self.peek() orelse return self.fail("unterminated element tag");
            if (byte == '/' or byte == '>') break;
            const attr_line = self.line;
            const attr_column = self.column;
            const attr_name = try self.parseName("attribute name");
            var value: []const u8 = "";
            self.skipWhitespace();
            if (self.consumeByte('=')) {
                self.skipWhitespace();
                value = try self.parseQuotedValue();
            }
            try attrs.append(self.arena, .{
                .name = attr_name,
                .value = value,
                .line = attr_line,
                .column = attr_column,
            });
        }

        var node = MarkupNode{
            .kind = nodeKindForName(name),
            .name = name,
            .attrs = attrs.items,
            .line = start_line,
            .column = start_column,
        };

        if (self.consumeByte('/')) {
            if (!self.consumeByte('>')) return self.fail("expected '>' after '/' in a self-closing tag");
            return node;
        }
        if (!self.consumeByte('>')) return self.fail("expected '>' to close the element tag");

        var children: std.ArrayListUnmanaged(MarkupNode) = .empty;
        while (true) {
            self.skipComments();
            const byte = self.peek() orelse return self.failAt(start_line, start_column, "element was never closed");
            if (byte == '<') {
                if (self.peekAt(1) == '/') {
                    try self.parseClosingTag(name);
                    break;
                }
                try children.append(self.arena, try self.parseElement());
                continue;
            }
            const text = self.takeText();
            const trimmed = std.mem.trim(u8, text, " \t\r\n");
            if (trimmed.len > 0) {
                try children.append(self.arena, .{
                    .kind = .text,
                    .text = trimmed,
                    .line = self.line,
                    .column = self.column,
                });
            }
        }

        node.children = children.items;
        return node;
    }

    fn parseClosingTag(self: *Parser, open_name: []const u8) ParseError!void {
        const line = self.line;
        const column = self.column;
        _ = self.consumeByte('<');
        _ = self.consumeByte('/');
        const name = try self.parseName("closing tag name");
        self.skipWhitespace();
        if (!self.consumeByte('>')) return self.fail("expected '>' in closing tag");
        if (!std.mem.eql(u8, name, open_name)) {
            return self.failAt(line, column, "closing tag does not match the open element");
        }
    }

    fn parseName(self: *Parser, what: []const u8) ParseError![]const u8 {
        const start = self.index;
        while (self.peek()) |byte| {
            const valid = (byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9') or byte == '-' or byte == '_';
            if (!valid) break;
            self.advance();
        }
        if (self.index == start) {
            self.diagnostic = .{ .line = self.line, .column = self.column, .message = what };
            return self.fail("expected a lowercase kebab-case name");
        }
        return self.source[start..self.index];
    }

    fn parseQuotedValue(self: *Parser) ParseError![]const u8 {
        if (!self.consumeByte('"')) return self.fail("expected '\"' to open an attribute value");
        const start = self.index;
        while (self.peek()) |byte| {
            if (byte == '"') {
                const value = self.source[start..self.index];
                self.advance();
                return value;
            }
            if (byte == '\n') return self.fail("attribute values may not contain newlines");
            self.advance();
        }
        return self.fail("unterminated attribute value");
    }

    fn takeText(self: *Parser) []const u8 {
        const start = self.index;
        while (self.peek()) |byte| {
            if (byte == '<') break;
            self.advance();
        }
        return self.source[start..self.index];
    }

    fn skipWhitespaceAndComments(self: *Parser) void {
        while (true) {
            const before = self.index;
            self.skipWhitespace();
            self.skipComments();
            if (self.index == before) return;
        }
    }

    fn skipComments(self: *Parser) void {
        while (std.mem.startsWith(u8, self.source[self.index..], "<!--")) {
            const end = std.mem.indexOfPos(u8, self.source, self.index + 4, "-->") orelse {
                // Unterminated comment: consume to EOF; parse loop reports it.
                while (self.peek() != null) self.advance();
                return;
            };
            while (self.index < end + 3) self.advance();
        }
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.peek()) |byte| {
            if (byte != ' ' and byte != '\t' and byte != '\r' and byte != '\n') return;
            self.advance();
        }
    }

    fn peek(self: *const Parser) ?u8 {
        if (self.index >= self.source.len) return null;
        return self.source[self.index];
    }

    fn peekAt(self: *const Parser, offset: usize) ?u8 {
        if (self.index + offset >= self.source.len) return null;
        return self.source[self.index + offset];
    }

    fn consumeByte(self: *Parser, byte: u8) bool {
        if (self.peek() == byte) {
            self.advance();
            return true;
        }
        return false;
    }

    fn advance(self: *Parser) void {
        if (self.source[self.index] == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        self.index += 1;
    }

    fn fail(self: *Parser, message: []const u8) ParseError {
        return self.failAt(self.line, self.column, message);
    }

    fn failAt(self: *Parser, line: usize, column: usize, message: []const u8) ParseError {
        self.diagnostic = .{ .line = line, .column = column, .message = message };
        return error.MarkupSyntax;
    }
};

fn nodeKindForName(name: []const u8) MarkupNodeKind {
    if (std.mem.eql(u8, name, "for")) return .for_block;
    if (std.mem.eql(u8, name, "if")) return .if_block;
    if (std.mem.eql(u8, name, "else")) return .else_block;
    if (std.mem.eql(u8, name, "template")) return .template_block;
    if (std.mem.eql(u8, name, "use")) return .use_block;
    return .element;
}

// ------------------------------------------------------- comptime parsing

/// Comptime counterpart of `Parser.parse` for `@embedFile`d sources: the
/// same `Parser` token-level helpers drive the scan (single source of truth
/// for the grammar), but attribute/child accumulation uses comptime slice
/// concatenation instead of an arena, and any syntax error becomes a
/// compile error carrying the line/column and message that the runtime
/// diagnostic would carry.
pub fn parseComptime(comptime source: []const u8) MarkupDocument {
    comptime {
        @setEvalBranchQuota(comptime_parse_quota_base + source.len * comptime_parse_quota_per_byte);
        var parser = Parser.init(undefined, source);
        var templates: []const MarkupNode = &.{};
        while (true) {
            parser.skipWhitespaceAndComments();
            if (parser.index >= parser.source.len and templates.len > 0) {
                failComptime(&parser, parser.fail("expected a view root element after the template definitions"));
            }
            const node = parseElementComptime(&parser);
            if (node.kind == .template_block) {
                templates = templates ++ &[_]MarkupNode{node};
                continue;
            }
            parser.skipWhitespaceAndComments();
            if (parser.index < parser.source.len) {
                failComptime(&parser, parser.fail("expected end of file after the root element"));
            }
            return .{ .templates = templates, .root = node };
        }
    }
}

/// Comptime parsing walks every byte through the shared scanner helpers, so
/// the branch quota scales with the source: a handful of comptime branches
/// per byte, with generous headroom for nesting.
const comptime_parse_quota_base = 20_000;
const comptime_parse_quota_per_byte = 200;

/// Comptime mirror of `Parser.parseElement`: identical control flow, with
/// `attrs ++`/`children ++` in place of the arena-backed lists.
fn parseElementComptime(comptime parser: *Parser) MarkupNode {
    const start_line = parser.line;
    const start_column = parser.column;
    if (!parser.consumeByte('<')) failComptime(parser, parser.fail("expected '<' to open an element"));
    const name = parser.parseName("element name") catch |err| failComptime(parser, err);

    var attrs: []const MarkupAttr = &.{};
    while (true) {
        parser.skipWhitespace();
        const byte = parser.peek() orelse failComptime(parser, parser.fail("unterminated element tag"));
        if (byte == '/' or byte == '>') break;
        const attr_line = parser.line;
        const attr_column = parser.column;
        const attr_name = parser.parseName("attribute name") catch |err| failComptime(parser, err);
        var value: []const u8 = "";
        parser.skipWhitespace();
        if (parser.consumeByte('=')) {
            parser.skipWhitespace();
            value = parser.parseQuotedValue() catch |err| failComptime(parser, err);
        }
        attrs = attrs ++ &[_]MarkupAttr{.{
            .name = attr_name,
            .value = value,
            .line = attr_line,
            .column = attr_column,
        }};
    }

    var node = MarkupNode{
        .kind = nodeKindForName(name),
        .name = name,
        .attrs = attrs,
        .line = start_line,
        .column = start_column,
    };

    if (parser.consumeByte('/')) {
        if (!parser.consumeByte('>')) failComptime(parser, parser.fail("expected '>' after '/' in a self-closing tag"));
        return node;
    }
    if (!parser.consumeByte('>')) failComptime(parser, parser.fail("expected '>' to close the element tag"));

    var children: []const MarkupNode = &.{};
    while (true) {
        parser.skipComments();
        const byte = parser.peek() orelse failComptime(parser, parser.failAt(start_line, start_column, "element was never closed"));
        if (byte == '<') {
            if (parser.peekAt(1) == '/') {
                parser.parseClosingTag(name) catch |err| failComptime(parser, err);
                break;
            }
            children = children ++ &[_]MarkupNode{parseElementComptime(parser)};
            continue;
        }
        const text = parser.takeText();
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len > 0) {
            children = children ++ &[_]MarkupNode{.{
                .kind = .text,
                .text = trimmed,
                .line = parser.line,
                .column = parser.column,
            }};
        }
    }

    node.children = children;
    return node;
}

/// Surface the parser's diagnostic (already positioned by the shared
/// helpers) as a compile error. The error value parameter exists so call
/// sites read like the runtime parser's `try`/`return self.fail(...)`.
fn failComptime(comptime parser: *const Parser, comptime err: ParseError) noreturn {
    _ = err;
    @compileError(std.fmt.comptimePrint("markup error at line {d}, column {d}: {s}", .{
        parser.diagnostic.line,
        parser.diagnostic.column,
        parser.diagnostic.message,
    }));
}

// ------------------------------------------------------------ expressions

pub const Expression = union(enum) {
    literal: []const u8,
    binding: []const u8,
    equals: struct { left: []const u8, right: []const u8 },
};

/// Parse an attribute value: either a plain literal or exactly one
/// sanctioned expression form — `{path}` or `{a == b}`. Mixed literal and
/// binding text is only allowed in text content (interpolation), not in
/// attribute values.
pub fn parseAttrExpression(value: []const u8) ?Expression {
    if (value.len == 0 or value[0] != '{') return .{ .literal = value };
    if (value[value.len - 1] != '}') return null;
    const inner = std.mem.trim(u8, value[1 .. value.len - 1], " ");
    if (inner.len == 0) return null;
    if (std.mem.indexOf(u8, inner, "==")) |eq| {
        const left = std.mem.trim(u8, inner[0..eq], " ");
        const right = std.mem.trim(u8, inner[eq + 2 ..], " ");
        if (!isBindingPath(left) or !isBindingPath(right)) return null;
        return .{ .equals = .{ .left = left, .right = right } };
    }
    if (!isBindingPath(inner)) return null;
    return .{ .binding = inner };
}

pub const MessageExpression = struct {
    tag: []const u8,
    /// Binding path for the payload, empty when the message carries none.
    payload: []const u8 = "",
};

/// Parse an `on-*` attribute value: `msg` or `msg:{path}`.
pub fn parseMessageExpression(value: []const u8) ?MessageExpression {
    if (std.mem.indexOfScalar(u8, value, ':')) |colon| {
        const tag = value[0..colon];
        const payload = value[colon + 1 ..];
        if (!isBindingPath(tag)) return null;
        if (payload.len < 3 or payload[0] != '{' or payload[payload.len - 1] != '}') return null;
        const path = payload[1 .. payload.len - 1];
        if (!isBindingPath(path)) return null;
        return .{ .tag = tag, .payload = path };
    }
    if (!isBindingPath(value)) return null;
    return .{ .tag = value };
}

fn isBindingPath(text: []const u8) bool {
    if (text.len == 0) return false;
    var segment_start = true;
    for (text) |byte| {
        if (segment_start) {
            if (!std.ascii.isAlphabetic(byte) and byte != '_') return false;
            segment_start = false;
            continue;
        }
        if (byte == '.') {
            segment_start = true;
            continue;
        }
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return !segment_start;
}

// ------------------------------------------------------------ validation

/// Element names the interpreter accepts (kept in sync by a test in
/// ui_markup_view_tests.zig). Covers every built-in component whose shape
/// fits the closed grammar; the deliberate exclusions (icon, image,
/// icon-button, data-grid, popover, menu-surface, segmented-control) are
/// documented next to the widget-kind coverage test in
/// ui_markup_view_tests.zig — write those as Zig view functions.
pub const known_element_names =
    // Flex, overlay, and scrolling containers.
    [_][]const u8{ "row", "column", "stack", "panel", "scroll", "list", "grid", "card" } ++
    // Row containers (children flow along the horizontal main axis).
    [_][]const u8{ "breadcrumb", "button-group", "pagination", "radio-group", "tabs", "toggle-group" } ++
    // Vertical containers.
    [_][]const u8{ "table", "table-row", "dropdown-menu" } ++
    // Overlay/surface containers (title via the text attribute).
    [_][]const u8{ "accordion", "alert", "bubble", "dialog", "drawer", "sheet", "resizable" } ++
    // Text-bearing leaves (label is the element content).
    [_][]const u8{ "text", "badge", "button", "toggle", "list-item", "menu-item", "status-bar" } ++
    [_][]const u8{ "avatar", "select", "switch", "table-cell", "toggle-button", "tooltip" } ++
    // Value controls and text entry.
    [_][]const u8{ "checkbox", "radio", "slider", "progress" } ++
    [_][]const u8{ "text-field", "search-field", "textarea", "input", "combobox" } ++
    // Plain leaves.
    [_][]const u8{ "separator", "spacer", "skeleton", "spinner" };

/// Elements whose content is a single run of text (with `{}`
/// interpolation) and that take no element children. Kept in sync with the
/// interpreter's `elementTakesText` by a test in ui_markup_view_tests.zig.
pub const known_text_leaf_element_names = [_][]const u8{
    "text",       "badge",         "button",  "toggle", "list-item",
    "menu-item",  "status-bar",    "avatar",  "select", "switch",
    "table-cell", "toggle-button", "tooltip",
};

pub const known_option_attrs = [_][]const u8{
    "text",       "placeholder", "value", "checked",     "selected",            "disabled",
    "variant",    "size",        "width", "height",      "grow",                "gap",
    "padding",    "main",        "cross", "virtualized", "virtual-item-extent", "key",
    "global-key", "role",        "label",
};

pub const known_events = [_][]const u8{ "press", "toggle", "change", "submit", "input" };

/// Elements whose widget kind the engine never hit-tests: layout and
/// decoration only, so pointer events pass through them and an `on-*`
/// handler on one can never fire. The validator rejects handlers here
/// instead of letting them silently do nothing. Derived from the engine's
/// hit-target predicate (`canvas.widgetKindHitTarget` in
/// widget_access.zig); a test in ui_markup_view_tests.zig keeps this name
/// list and that predicate in lockstep so drift is impossible.
pub const known_non_hit_target_element_names = [_][]const u8{
    "row",          "column",     "stack",      "spacer",       "grid",
    "list",         "table",      "table-row",  "breadcrumb",   "button-group",
    "pagination",   "radio-group", "tabs",      "toggle-group", "tooltip",
    "avatar",       "badge",      "separator",  "skeleton",     "spinner",
};

pub const non_hit_target_handler_message = "on-* handlers never fire here: this element is layout/decoration and is never a hit target - put the handler on a leaf like list-item or text, or on a control (button, checkbox) inside it";

/// Markup attributes that reference a color design token by name. Values
/// must be literal `ColorTokens` field names (`known_color_token_names`);
/// the builder resolves them against live tokens in `finalizeWithTokens`.
/// `border-color` (not bare `border`) keeps the name free for a future
/// border-width shorthand.
pub const known_color_style_attrs = [_][]const u8{
    "background", "foreground", "accent", "accent-foreground", "border-color", "focus-ring",
};

/// The field names of `canvas.ColorTokens`, kept in sync by a test in
/// ui_markup_view_tests.zig (this module stays std-only).
pub const known_color_token_names = [_][]const u8{
    "background",  "surface",     "surface_subtle",   "surface_pressed",
    "text",        "text_muted",  "border",           "accent",
    "accent_text", "destructive", "destructive_text", "focus_ring",
    "shadow",      "disabled",
};

/// The field names of `canvas.RadiusTokens` (same sync test).
pub const known_radius_token_names = [_][]const u8{ "sm", "md", "lg", "xl" };

pub const style_token_literal_message = "style token attributes take a literal token name - dynamic styling stays in Zig";
pub const unknown_color_token_message = "unknown color token: color style attributes take a canvas ColorTokens field name (background, surface, surface_subtle, surface_pressed, text, text_muted, border, accent, accent_text, destructive, destructive_text, focus_ring, shadow, disabled)";
pub const unknown_radius_token_message = "unknown radius token: radius takes a canvas RadiusTokens field name (sm, md, lg, xl)";

pub const invalid_expression_message = "invalid expression: values are a literal, one {binding}, or one {a == b} equality - no other operators or calls (put logic in a model function)";
pub const arena_scalar_equality_message = "arena-computed bindings cannot be compared with == - compare the source fields directly, or bind a pub fn returning bool";
pub const markdown_source_message = "markdown requires a source attribute with one {binding} naming the markdown text (a []const u8 field or fn - arena fns work)";
pub const markdown_children_message = "markdown takes no children or text content - the source binding provides the markdown";
pub const markdown_attr_message = "unknown attribute for markdown - it takes source, on-link, on-details, and details-expanded";
pub const markdown_on_link_message = "on-link takes a bare Msg tag whose payload is the pressed link URL (a []const u8 variant, like open_url: []const u8)";
pub const markdown_on_details_message = "on-details takes a bare Msg tag whose payload is the details block index (a usize variant, like toggle_details: usize)";
pub const markdown_details_expanded_message = "details-expanded takes one {binding} naming a []const bool iterable (a model field, pub decl, or fn - the same sources for each accepts)";
pub const text_leaf_children_message = "this element takes text content only - wrap element children in a container (row, column, stack)";
pub const text_leaf_single_run_message = "text elements take a single run of text";
pub const table_row_parent_message = "table-row is only allowed inside a table (structure tags in between are fine)";
pub const table_cell_parent_message = "table-cell is only allowed inside a table-row (structure tags in between are fine)";
pub const template_top_level_message = "template definitions are only allowed at the top of the file, before the view root";
pub const template_name_message = "template requires a name attribute";
pub const template_unique_name_message = "template names must be unique";
pub const template_args_message = "template args must be space-separated names (args=\"title cards\")";
pub const template_attrs_message = "template takes only name and args attributes";
pub const template_one_child_message = "template takes exactly one element child (wrap siblings in a container)";
pub const use_template_attr_message = "use requires a template attribute naming a template defined at the top of the file";
pub const use_undefined_template_message = "use references an undefined template (define <template name=\"...\"> before the view root)";
pub const use_earlier_template_message = "use may only reference templates defined earlier in the file";
pub const use_missing_arg_message = "use is missing an argument the template declares in args";
pub const use_extra_arg_message = "use passes an argument the template does not declare in args";
pub const use_no_children_message = "use takes no children (the template body is built in its place)";

/// Model-agnostic structural validation: unknown elements or attributes,
/// malformed expressions, misshapen structure tags, and template/use
/// wiring. Binding paths and message tags are checked against the concrete
/// Model/Msg by the interpreter; this pass is what
/// `zero-native markup check` runs.
pub fn validate(document: MarkupDocument) ?MarkupErrorInfo {
    for (document.templates, 0..) |template_node, index| {
        if (validateTemplate(document, template_node, index)) |info| return info;
    }
    return validateNode(document, document.root, null, document.templates.len);
}

fn validateTemplate(document: MarkupDocument, node: MarkupNode, index: usize) ?MarkupErrorInfo {
    const name = node.attr("name") orelse return errorAt(node, template_name_message);
    if (!isTemplateName(name)) return errorAt(node, template_name_message);
    for (document.templates[0..index]) |earlier| {
        const earlier_name = earlier.attr("name") orelse continue;
        if (std.mem.eql(u8, earlier_name, name)) return errorAt(node, template_unique_name_message);
    }
    for (node.attrs) |attribute| {
        if (std.mem.eql(u8, attribute.name, "name")) continue;
        if (std.mem.eql(u8, attribute.name, "args")) {
            var args = templateArgs(node);
            while (args.next()) |arg_name| {
                if (!isBindingName(arg_name)) {
                    return .{ .line = attribute.line, .column = attribute.column, .message = template_args_message };
                }
            }
            continue;
        }
        return .{ .line = attribute.line, .column = attribute.column, .message = template_attrs_message };
    }
    if (node.children.len != 1 or node.children[0].kind != .element) {
        return errorAt(node, template_one_child_message);
    }
    // The body sees templates defined before this one, which also rules
    // out recursion. The body root has no known parent element, so
    // parent-scoped rules (table-row in table) are checked at use sites of
    // the surrounding markup, not here.
    return validateNode(document, node.children[0], null, index);
}

fn validateUse(document: MarkupDocument, node: MarkupNode, template_limit: usize) ?MarkupErrorInfo {
    const name = node.attr("template") orelse return errorAt(node, use_template_attr_message);
    const index = document.templateIndex(name) orelse return errorAt(node, use_undefined_template_message);
    if (index >= template_limit) return errorAt(node, use_earlier_template_message);
    if (node.children.len != 0) return errorAt(node, use_no_children_message);
    const template_node = document.templates[index];
    var args = templateArgs(template_node);
    while (args.next()) |arg_name| {
        if (node.attr(arg_name) == null) return errorAt(node, use_missing_arg_message);
    }
    for (node.attrs) |attribute| {
        if (std.mem.eql(u8, attribute.name, "template")) continue;
        if (!templateDeclaresArg(template_node, attribute.name)) {
            return .{ .line = attribute.line, .column = attribute.column, .message = use_extra_arg_message };
        }
        if (parseAttrExpression(attribute.value) == null) {
            return .{ .line = attribute.line, .column = attribute.column, .message = invalid_expression_message };
        }
    }
    return null;
}

/// `<markdown>` is a leaf whose content comes entirely from its `source`
/// binding: no children, a closed attribute set, and bare message tags for
/// `on-link`/`on-details` (the runtime supplies their payloads). Whether
/// the bindings and tags exist on the concrete Model/Msg is the engines'
/// check, exactly like ordinary bindings.
fn validateMarkdown(node: MarkupNode) ?MarkupErrorInfo {
    for (node.children) |child| {
        return errorAt(child, markdown_children_message);
    }
    var has_source = false;
    for (node.attrs) |attribute| {
        if (std.mem.eql(u8, attribute.name, "source")) {
            has_source = true;
            const expression = parseAttrExpression(attribute.value);
            if (expression == null or expression.? != .binding) {
                return .{ .line = attribute.line, .column = attribute.column, .message = markdown_source_message };
            }
            continue;
        }
        if (std.mem.eql(u8, attribute.name, "on-link")) {
            const expression = parseMessageExpression(attribute.value);
            if (expression == null or expression.?.payload.len != 0) {
                return .{ .line = attribute.line, .column = attribute.column, .message = markdown_on_link_message };
            }
            continue;
        }
        if (std.mem.eql(u8, attribute.name, "on-details")) {
            const expression = parseMessageExpression(attribute.value);
            if (expression == null or expression.?.payload.len != 0) {
                return .{ .line = attribute.line, .column = attribute.column, .message = markdown_on_details_message };
            }
            continue;
        }
        if (std.mem.eql(u8, attribute.name, "details-expanded")) {
            const expression = parseAttrExpression(attribute.value);
            if (expression == null or expression.? != .binding) {
                return .{ .line = attribute.line, .column = attribute.column, .message = markdown_details_expanded_message };
            }
            continue;
        }
        return .{ .line = attribute.line, .column = attribute.column, .message = markdown_attr_message };
    }
    if (!has_source) return errorAt(node, markdown_source_message);
    return null;
}

/// `parent_element` is the name of the nearest enclosing element, looking
/// through structure tags (`for`/`if`/`else`), or null at the view root and
/// at a template body root.
fn validateNode(document: MarkupDocument, node: MarkupNode, parent_element: ?[]const u8, template_limit: usize) ?MarkupErrorInfo {
    switch (node.kind) {
        .text => return null,
        .template_block => return errorAt(node, template_top_level_message),
        .use_block => return validateUse(document, node, template_limit),
        .element => {
            if (std.mem.eql(u8, node.name, "markdown")) {
                return validateMarkdown(node);
            }
            if (!nameInList(node.name, &known_element_names)) {
                return errorAt(node, "unknown element");
            }
            if (std.mem.eql(u8, node.name, "table-row")) {
                if (parent_element) |parent_name| {
                    if (!std.mem.eql(u8, parent_name, "table")) return errorAt(node, table_row_parent_message);
                }
            }
            if (std.mem.eql(u8, node.name, "table-cell")) {
                if (parent_element) |parent_name| {
                    if (!std.mem.eql(u8, parent_name, "table-row")) return errorAt(node, table_cell_parent_message);
                }
            }
            if (nameInList(node.name, &known_text_leaf_element_names)) {
                var text_runs: usize = 0;
                for (node.children) |child| {
                    if (child.kind != .text) return errorAt(child, text_leaf_children_message);
                    text_runs += 1;
                    if (text_runs > 1) return errorAt(child, text_leaf_single_run_message);
                }
            }
            for (node.attrs) |attribute| {
                if (std.mem.startsWith(u8, attribute.name, "on-")) {
                    if (!nameInList(attribute.name[3..], &known_events)) {
                        return .{ .line = attribute.line, .column = attribute.column, .message = "unknown event attribute" };
                    }
                    if (nameInList(node.name, &known_non_hit_target_element_names)) {
                        return .{ .line = attribute.line, .column = attribute.column, .message = non_hit_target_handler_message };
                    }
                    if (parseMessageExpression(attribute.value) == null) {
                        return .{ .line = attribute.line, .column = attribute.column, .message = "invalid message expression: on-* takes a Msg tag (\"add\") or tag with one binding payload (\"toggle:{item.id}\")" };
                    }
                    continue;
                }
                if (nameInList(attribute.name, &known_color_style_attrs)) {
                    if (!nameInList(attribute.value, &known_color_token_names)) {
                        const message = if (parseAttrExpression(attribute.value)) |expression|
                            (if (expression == .literal) unknown_color_token_message else style_token_literal_message)
                        else
                            style_token_literal_message;
                        return .{ .line = attribute.line, .column = attribute.column, .message = message };
                    }
                    continue;
                }
                if (std.mem.eql(u8, attribute.name, "radius")) {
                    if (!nameInList(attribute.value, &known_radius_token_names)) {
                        const message = if (parseAttrExpression(attribute.value)) |expression|
                            (if (expression == .literal) unknown_radius_token_message else style_token_literal_message)
                        else
                            style_token_literal_message;
                        return .{ .line = attribute.line, .column = attribute.column, .message = message };
                    }
                    continue;
                }
                if (!nameInList(attribute.name, &known_option_attrs)) {
                    return .{ .line = attribute.line, .column = attribute.column, .message = "unknown attribute" };
                }
                if (parseAttrExpression(attribute.value) == null) {
                    return .{ .line = attribute.line, .column = attribute.column, .message = invalid_expression_message };
                }
            }
        },
        .for_block => {
            if (parent_element == null) return errorAt(node, "for is only allowed inside an element");
            if (node.attr("each") == null) return errorAt(node, "for requires an each attribute");
            if (node.attr("as") == null) return errorAt(node, "for requires an as attribute");
            if (node.children.len != 1 or (node.children[0].kind != .element and node.children[0].kind != .use_block)) {
                return errorAt(node, "for takes exactly one element child");
            }
        },
        .if_block => {
            if (parent_element == null) return errorAt(node, "if is only allowed inside an element");
            const test_value = node.attr("test") orelse return errorAt(node, "if requires a test attribute");
            if (parseAttrExpression(test_value) == null) return errorAt(node, "invalid expression: test takes one {binding} or {a == b} equality");
        },
        .else_block => {},
    }
    // Structure tags are transparent for parent-scoped rules: their
    // children still sit inside the enclosing element.
    const child_parent: ?[]const u8 = switch (node.kind) {
        .element => node.name,
        .for_block, .if_block, .else_block => parent_element,
        else => null,
    };
    var previous_kind: ?MarkupNodeKind = null;
    for (node.children) |child| {
        if (child.kind == .else_block and previous_kind != .if_block) {
            return errorAt(child, "else must directly follow an if");
        }
        if (validateNode(document, child, child_parent, template_limit)) |info| {
            return info;
        }
        previous_kind = child.kind;
    }
    return null;
}

/// A single undotted binding-path segment: template arg names (they must
/// be resolvable as binding heads).
fn isBindingName(text: []const u8) bool {
    return isBindingPath(text) and std.mem.indexOfScalar(u8, text, '.') == null;
}

/// A lowercase kebab-case name, like element names: template names
/// ("board-column") are referenced by `use`, never by bindings.
fn isTemplateName(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!(text[0] >= 'a' and text[0] <= 'z')) return false;
    for (text) |byte| {
        const valid = (byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9') or byte == '-' or byte == '_';
        if (!valid) return false;
    }
    return true;
}

fn nameInList(name: []const u8, list: []const []const u8) bool {
    for (list) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn errorAt(node: MarkupNode, message: []const u8) MarkupErrorInfo {
    return .{ .line = node.line, .column = node.column, .message = message };
}
