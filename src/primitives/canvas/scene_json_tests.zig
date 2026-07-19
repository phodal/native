const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("root.zig");

test "scene JSON round-trips commands images and registered fonts into SVG" {
    const stops = [_]canvas.GradientStop{
        .{ .offset = 0, .color = canvas.Color.rgb8(12, 18, 28) },
        .{ .offset = 1, .color = canvas.Color.rgb8(92, 220, 180) },
    };
    const path = [_]canvas.PathElement{
        .{ .verb = .move_to, .points = .{ .init(8, 8), .{}, .{} } },
        .{ .verb = .line_to, .points = .{ .init(30, 8), .{}, .{} } },
        .{ .verb = .quad_to, .points = .{ .init(36, 18), .init(30, 28), .{} } },
        .{ .verb = .close },
    };
    const pixels = [_]u8{ 255, 0, 0, 255, 0, 120, 255, 255 };
    const images = [_]canvas.ReferenceImage{.{
        .id = 77,
        .width = 2,
        .height = 1,
        .pixels = &pixels,
        .content_fingerprint = 1234,
    }};
    const fonts = [_]canvas.ReferenceFont{.{ .id = 900, .face = &canvas.font_ttf.geist_regular }};
    const commands = [_]canvas.CanvasCommand{
        .{ .push_clip = .{ .id = 1, .rect = .init(0, 0, 120, 80), .radius = .all(8) } },
        .{ .fill_rect = .{ .id = 2, .rect = .init(0, 0, 120, 80), .fill = .{ .linear_gradient = .{ .start = .init(0, 0), .end = .init(120, 80), .stops = &stops } } } },
        .{ .fill_path = .{ .id = 3, .elements = &path, .fill = .{ .color = canvas.Color.rgb8(245, 245, 240) } } },
        .{ .draw_image = .{ .id = 4, .image_id = 77, .dst = .init(42, 8, 32, 24), .fit = .contain, .sampling = .nearest, .radius = .all(4) } },
        .{ .draw_text = .{ .id = 5, .font_id = 900, .size = 16, .origin = .init(8, 58), .color = canvas.Color.rgb8(250, 250, 250), .text = "Portable scene", .text_layout = .{ .max_width = 100, .line_height = 20, .wrap = .none, .alignment = .center, .overflow = .clip } } },
        .pop_clip,
    };
    const original = canvas.SceneJsonDocument{
        .scene = .{
            .display_list = .{ .commands = &commands },
            .size = geometry.SizeF.init(120, 80),
            .resources = .{ .images = &images, .fonts = &fonts },
        },
        .background = canvas.Color.rgb8(4, 6, 10),
        .title = "Native & portable",
        .description = "One scene, multiple exporters.",
    };

    var encoded: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer encoded.deinit();
    try canvas.writeSceneJson(&encoded.writer, original);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const decoded = try canvas.parseSceneJson(arena.allocator(), encoded.written());
    try std.testing.expectEqual(@as(f32, 120), decoded.scene.size.width);
    try std.testing.expectEqual(@as(usize, commands.len), decoded.scene.display_list.commands.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.scene.resources.images.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.scene.resources.fonts.len);
    try std.testing.expectEqualStrings("Native & portable", decoded.title);
    try std.testing.expectEqualSlices(u8, &pixels, decoded.scene.resources.images[0].pixels);
    try std.testing.expectEqual(@as(u64, 1234), decoded.scene.resources.images[0].content_fingerprint);
    try std.testing.expectEqualStrings(canvas.font_ttf.geist_regular.bytes, decoded.scene.resources.fonts[0].face.bytes);

    var reencoded: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer reencoded.deinit();
    try canvas.writeSceneJson(&reencoded.writer, decoded);
    try std.testing.expectEqualStrings(encoded.written(), reencoded.written());

    var svg: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer svg.deinit();
    var options = decoded.svgOptions();
    options.mode = .vector;
    try canvas.writeSvg(arena.allocator(), &svg.writer, decoded.scene, options);
    try std.testing.expect(std.mem.indexOf(u8, svg.written(), "linearGradient") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg.written(), "native-image-77") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg.written(), "Native &amp; portable") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg.written(), "<text") == null);
}

test "scene JSON rejects incompatible versions malformed resources and unknown commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.UnsupportedSceneVersion, canvas.parseSceneJson(arena.allocator(), "{\"schema\":\"native.canvas.scene\",\"version\":2,\"width\":1,\"height\":1,\"displayList\":{\"commands\":[]}}"));
    try std.testing.expectError(error.InvalidSceneResource, canvas.parseSceneJson(arena.allocator(), "{\"schema\":\"native.canvas.scene\",\"version\":1,\"width\":1,\"height\":1,\"displayList\":{\"commands\":[]},\"resources\":{\"images\":[{\"id\":1,\"width\":1,\"height\":1,\"rgbaBase64\":\"not base64\"}]}}"));
    try std.testing.expectError(error.InvalidSceneValue, canvas.parseSceneJson(arena.allocator(), "{\"schema\":\"native.canvas.scene\",\"version\":1,\"width\":1,\"height\":1,\"displayList\":{\"commands\":[{\"op\":\"launch_process\"}]}}"));
}

test "scene JSON parses every current display-list command" {
    const source =
        "{\"schema\":\"native.canvas.scene\",\"version\":1,\"width\":64,\"height\":64,\"displayList\":{\"commands\":[" ++
        "{\"op\":\"push_clip\",\"id\":1,\"rect\":[0,0,64,64],\"radius\":[1,2,3,4]}," ++
        "{\"op\":\"pop_clip\"}," ++
        "{\"op\":\"push_opacity\",\"opacity\":0.5}," ++
        "{\"op\":\"pop_opacity\"}," ++
        "{\"op\":\"transform\",\"matrix\":[1,0,0,1,2,3]}," ++
        "{\"op\":\"fill_rect\",\"id\":2,\"rect\":[1,1,8,8],\"fill\":{\"kind\":\"color\",\"color\":[1,0,0,1]}}," ++
        "{\"op\":\"stroke_rect\",\"id\":3,\"rect\":[1,1,8,8],\"radius\":[0,0,0,0],\"stroke\":{\"width\":1,\"fill\":{\"kind\":\"color\",\"color\":[1,1,1,1]}}}," ++
        "{\"op\":\"fill_rounded_rect\",\"id\":4,\"rect\":[1,1,8,8],\"radius\":[2,2,2,2],\"fill\":{\"kind\":\"color\",\"color\":[0,1,0,1]}}," ++
        "{\"op\":\"draw_line\",\"id\":5,\"from\":[0,0],\"to\":[8,8],\"stroke\":{\"width\":2,\"fill\":{\"kind\":\"color\",\"color\":[1,1,1,1]}}}," ++
        "{\"op\":\"fill_path\",\"id\":6,\"path\":[{\"verb\":\"move_to\",\"points\":[[0,0]]},{\"verb\":\"close\",\"points\":[]}],\"fill\":{\"kind\":\"color\",\"color\":[1,1,1,1]}}," ++
        "{\"op\":\"stroke_path\",\"id\":7,\"path\":[{\"verb\":\"move_to\",\"points\":[[0,0]]},{\"verb\":\"line_to\",\"points\":[[2,2]]}],\"stroke\":{\"width\":1,\"fill\":{\"kind\":\"color\",\"color\":[1,1,1,1]}},\"cap\":\"round\"}," ++
        "{\"op\":\"draw_image\",\"id\":8,\"image\":9,\"dst\":[0,0,2,2],\"src\":null,\"opacity\":1,\"fit\":\"stretch\",\"sampling\":\"linear\"}," ++
        "{\"op\":\"draw_text\",\"id\":9,\"font\":0,\"size\":12,\"origin\":[1,10],\"color\":[1,1,1,1],\"text\":\"x\",\"glyphs\":[{\"id\":1,\"x\":0,\"y\":0,\"advance\":6,\"textStart\":0,\"textLen\":1}],\"layout\":{\"maxWidth\":20,\"lineHeight\":14,\"wrap\":\"word\",\"align\":\"start\",\"overflow\":\"ellipsis\"}}," ++
        "{\"op\":\"shadow\",\"id\":10,\"rect\":[0,0,4,4],\"radius\":[1,1,1,1],\"offset\":[1,2],\"blur\":3,\"spread\":1,\"color\":[0,0,0,0.5]}," ++
        "{\"op\":\"blur\",\"id\":11,\"rect\":[0,0,4,4],\"radius\":2}" ++
        "]}}";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const document = try canvas.parseSceneJson(arena.allocator(), source);
    try std.testing.expectEqual(@as(usize, 15), document.scene.display_list.commands.len);
    try std.testing.expectEqual(canvas.LineCap.round, document.scene.display_list.commands[10].stroke_path.cap);
    try std.testing.expectEqual(canvas.TextOverflow.ellipsis, document.scene.display_list.commands[12].draw_text.text_layout.?.overflow);
}
