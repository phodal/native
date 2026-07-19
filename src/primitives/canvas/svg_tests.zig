const std = @import("std");
const geometry = @import("geometry");
const canvas = @import("root.zig");

test "vector SVG preserves rounded clip transforms gradients and glyph outlines" {
    const stops = [_]canvas.GradientStop{
        .{ .offset = 0, .color = canvas.Color.rgb8(13, 15, 11) },
        .{ .offset = 1, .color = canvas.Color.rgb8(215, 255, 114) },
    };
    var commands: [12]canvas.CanvasCommand = undefined;
    var builder = canvas.Builder.init(&commands);
    try builder.transform(canvas.Affine.translate(4, 6));
    try builder.fillRect(.{
        .rect = .init(0, 0, 320, 180),
        .fill = .{ .linear_gradient = .{ .start = .init(0, 0), .end = .init(320, 180), .stops = &stops } },
    });
    try builder.pushClip(.{ .rect = .init(8, 8, 304, 164), .radius = .all(12) });
    try builder.pushOpacity(0.8);
    try builder.drawText(.{
        .font_id = canvas.default_mono_font_id,
        .size = 18,
        .origin = .init(20, 48),
        .color = canvas.Color.rgb8(230, 233, 221),
        .text = "Native <UI>",
    });
    try builder.popOpacity();
    try builder.popClip();

    var output_buffer: [64 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buffer);
    try canvas.writeSvg(std.testing.allocator, &writer, .{
        .display_list = builder.displayList(),
        .size = geometry.SizeF.init(320, 180),
    }, .{ .mode = .vector, .title = "Native & UI" });
    const svg = writer.buffered();
    try std.testing.expect(std.mem.startsWith(u8, svg, "<svg xmlns=\"http://www.w3.org/2000/svg\""));
    try std.testing.expect(std.mem.indexOf(u8, svg, "Native &amp; UI") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "linearGradient id=\"gradient-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "clipPath id=\"clip-2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "A12 12") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "transform=\"matrix(1 0 0 1 4 6)\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "opacity=\"0.8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<text") == null);
}

test "vector SVG embeds reusable image resources with crop fit sampling and radius" {
    const pixels = [_]u8{
        255, 0, 0,   255, 0,   255, 0,   255,
        0,   0, 255, 255, 255, 255, 255, 255,
    };
    const images = [_]canvas.ReferenceImage{.{
        .id = 7,
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    }};
    const commands = [_]canvas.CanvasCommand{.{ .draw_image = .{
        .image_id = 7,
        .src = .init(0, 0, 1, 2),
        .dst = .init(10, 12, 40, 24),
        .opacity = 0.75,
        .fit = .cover,
        .sampling = .nearest,
        .radius = .all(6),
    } }};
    var output_buffer: [16 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buffer);
    try canvas.writeSvg(std.testing.allocator, &writer, .{
        .display_list = .{ .commands = &commands },
        .size = geometry.SizeF.init(80, 60),
        .resources = .{ .images = &images },
    }, .{ .mode = .vector });
    const svg = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"native-image-7\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "data:image/png;base64,iVBORw0KGgo") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "viewBox=\"0 0 1 2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "preserveAspectRatio=\"xMidYMid slice\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "image-rendering=\"pixelated\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "clip-path=\"url(#image-clip-0)\"") != null);
}

test "missing deterministic images fail before output unless omission is explicit" {
    const commands = [_]canvas.CanvasCommand{.{ .draw_image = .{
        .image_id = 99,
        .dst = .init(0, 0, 20, 20),
    } }};
    var output_buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buffer);
    try std.testing.expectError(error.MissingImageResource, canvas.writeSvg(std.testing.allocator, &writer, .{
        .display_list = .{ .commands = &commands },
        .size = geometry.SizeF.init(20, 20),
    }, .{}));
    try std.testing.expectEqual(@as(usize, 0), writer.buffered().len);

    var omit_writer = std.Io.Writer.fixed(&output_buffer);
    try canvas.writeSvg(std.testing.allocator, &omit_writer, .{
        .display_list = .{ .commands = &commands },
        .size = geometry.SizeF.init(20, 20),
    }, .{ .missing_images = .omit });
    try std.testing.expect(std.mem.indexOf(u8, omit_writer.buffered(), "omitted Native SDK image 99") != null);
}

test "auto mode reference-rasterizes backdrop blur while vector mode is strict" {
    const commands = [_]canvas.CanvasCommand{
        .{ .fill_rect = .{ .rect = .init(0, 0, 12, 12), .fill = .{ .color = canvas.Color.rgb8(220, 20, 20) } } },
        .{ .blur = .{ .rect = .init(0, 0, 12, 12), .radius = 2 } },
    };
    const scene = canvas.SvgScene{
        .display_list = .{ .commands = &commands },
        .size = geometry.SizeF.init(12, 12),
    };

    var vector_buffer: [4096]u8 = undefined;
    var vector_writer = std.Io.Writer.fixed(&vector_buffer);
    try std.testing.expectError(error.UnsupportedVectorEffect, canvas.writeSvg(std.testing.allocator, &vector_writer, scene, .{ .mode = .vector }));
    try std.testing.expectEqual(@as(usize, 0), vector_writer.buffered().len);

    var raster_buffer: [16 * 1024]u8 = undefined;
    var raster_writer = std.Io.Writer.fixed(&raster_buffer);
    try canvas.writeSvg(std.testing.allocator, &raster_writer, scene, .{});
    const svg = raster_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, svg, "<image x=\"0\" y=\"0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "data:image/png;base64,iVBORw0KGgo") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "data-native-blur") == null);
}

test "SVG scene borrows frame resources and surface size" {
    const frame = canvas.CanvasFrame{
        .surface_size = geometry.SizeF.init(48, 32),
        .display_list = .{},
    };
    const scene = canvas.SvgScene.fromFrame(&frame);
    try std.testing.expectEqual(@as(f32, 48), scene.size.width);
    try std.testing.expectEqual(@as(f32, 32), scene.size.height);
    try std.testing.expectEqual(@as(usize, 0), scene.resources.images.len);
}

test "reference-raster mode rejects dimensions that cannot fit usize" {
    var output_buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buffer);
    try std.testing.expectError(error.InvalidSceneSize, canvas.writeSvg(std.testing.allocator, &writer, .{
        .display_list = .{},
        .size = geometry.SizeF.init(std.math.floatMax(f32), 1),
    }, .{ .mode = .reference_raster }));
}
