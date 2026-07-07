//! soundboard views. Markup-first: the header, the now-playing bar, and
//! the album detail heading are compiled `.native` views (see
//! header.native / nowplaying.native / album_title.native); this file
//! holds the Zig-only sections the closed markup grammar cannot express —
//! rounded-square cover images (`ElementOptions.image` outside the
//! avatar), the album grid's width-derived column count, and per-track
//! native context menus — plus the root view that composes all of it
//! into one tree.

const std = @import("std");
const native_sdk = @import("native_sdk");
const model_mod = @import("model.zig");

const canvas = native_sdk.canvas;

pub const Model = model_mod.Model;
pub const Msg = model_mod.Msg;
pub const Ui = canvas.Ui(Msg);

pub const header_markup = @embedFile("header.native");
pub const nowplaying_markup = @embedFile("nowplaying.native");
pub const CompiledHeaderView = canvas.CompiledMarkupView(Model, Msg, header_markup);
pub const CompiledNowPlayingView = canvas.CompiledMarkupView(Model, Msg, nowplaying_markup);

// The album detail heading: a markup span paragraph (one bold 1.9x-scaled
// run bound to the open album's title), compiled like the other fragments
// and composed into the Zig detail column. The tests hold it
// widget-for-widget equal to the builder paragraph it replaced.
pub const AlbumTitleView = canvas.CompiledMarkupView(Model, Msg, @embedFile("album_title.native"));

// The album grid is ADAPTIVE: the layout system's grid takes a fixed
// column count (rows and columns never flow-wrap children), so the
// column count is derived here, per rebuild, from the canvas width the
// model tracks (`canvas_resized`, mirrored from presented frames). The
// rule is the standard adaptive-grid register: as many min-width tiles
// as fit the row, the leftover split evenly — tiles grow modestly until
// one more column fits, then snap back toward the minimum.
/// The narrowest an album tile may get. Sized so the cover (tile width
/// minus the hover-wash inset on both sides) never drops below the
/// generous cover the fixed four-column grid established.
const min_tile_width: f32 = 232;
/// Gap between bare tiles. Tighter than the old carded grid on purpose:
/// with no card chrome the gap IS the whole separation between covers,
/// and the bare music-library register reads best with covers closer
/// together than boxed cards were.
const grid_gap: f32 = 12;
/// Inset between the tile's hover/press wash and the cover art: on a
/// bare tile the wash must show AROUND the art to read at all (the art
/// would paint over a same-sized wash), so each tile keeps a thin halo.
const tile_padding: f32 = 8;
/// Vertical gap between the cover and the title/artist block.
const cover_text_gap: f32 = 8;
/// The title + artist block's height (one body line over one small
/// line), used to derive the tile's total height from its width.
const tile_text_height: f32 = 36;
const detail_cover_size: f32 = 184;
const content_padding: f32 = 24;

/// The width→columns rule, answered for one canvas width.
pub const GridFit = struct {
    /// How many min-width tiles (plus gaps) fit the content row.
    columns: usize,
    /// The evenly-grown tile width at that column count.
    tile_width: f32,
};

/// Columns = how many minimum-width tiles fit the padded content row;
/// tile width = the row split evenly at that count. Never below one
/// column, and the floor guard keeps the math total for degenerate
/// widths (a zero-sized test surface).
pub fn gridFit(canvas_width: f32) GridFit {
    const available = @max(min_tile_width, canvas_width - content_padding * 2);
    const fitting = @floor((available + grid_gap) / (min_tile_width + grid_gap));
    const columns: usize = @intFromFloat(@max(1, fitting));
    const gaps = grid_gap * @as(f32, @floatFromInt(columns - 1));
    const tile_width = (available - gaps) / @as(f32, @floatFromInt(columns));
    return .{ .columns = columns, .tile_width = tile_width };
}

pub fn rootView(ui: *Ui, model: *const Model) Ui.Node {
    return ui.column(.{ .grow = 1, .style_tokens = .{ .background = .background } }, .{
        CompiledHeaderView.build(ui, model),
        contentView(ui, model),
        CompiledNowPlayingView.build(ui, model),
    });
}

fn contentView(ui: *Ui, model: *const Model) Ui.Node {
    return switch (model.tab) {
        .albums => if (model.open_album) |album_id|
            albumDetailView(ui, model, album_id)
        else
            albumGridView(ui, model),
        .songs => songsView(ui, model),
    };
}

// ------------------------------------------------------------- album grid

fn albumGridView(ui: *Ui, model: *const Model) Ui.Node {
    const cells = model.visibleAlbums(ui.arena);
    // Controlled scroll: the model stores the applied offset
    // (`grid_scrolled`) and echoes it back, so a rebuild mid-gesture
    // (a progress tick, a search keystroke) can never reset the region.
    return ui.scroll(.{
        .grow = 1,
        .value = model.grid_scroll,
        .on_scroll = Ui.scrollMsg(.grid_scrolled),
        .semantics = .{ .label = "Album grid" },
    }, ui.column(.{ .padding = content_padding, .gap = 18 }, .{
        sectionHeading(ui, "Albums", ui.fmt("{d} of {d}", .{ cells.len, model_mod.albums.len })),
        if (cells.len == 0) emptyState(ui, model) else albumGrid(ui, model, cells),
    }));
}

fn albumGrid(ui: *Ui, model: *const Model, cells: []const model_mod.AlbumCell) Ui.Node {
    const fit = gridFit(model.canvas_width);
    // The grid node is EXPLICITLY sized to its shown columns rather than
    // stretched to the row, because the engine divides the grid's width
    // evenly among its columns: an exact width makes each cell exactly
    // one tile wide, and a short result set (a narrow search) keeps
    // tile-sized covers left-aligned instead of ballooning across the
    // row. The tail row left-aligns the same way — cells fill in row
    // order from the leading edge.
    const columns = @min(fit.columns, cells.len);
    const row_width = @as(f32, @floatFromInt(columns)) * (fit.tile_width + grid_gap) - grid_gap;
    return ui.el(.grid, .{
        .width = row_width,
        .columns = columns,
        .gap = grid_gap,
        .semantics = .{ .role = .list, .label = "Albums" },
    }, ui.eachCtx(fit, cells, albumKey, albumTile));
}

fn albumKey(cell: *const model_mod.AlbumCell) canvas.UiKey {
    return canvas.uiKey(cell.id);
}

/// One bare album tile: the cover IS the tile — no card fill, border, or
/// shadow around it (the flat `list_item` composite, the same chromeless
/// register the track rows use). NO state wash at all: hover changes
/// nothing visually — the pointer cursor is the whole hover affordance
/// on a cover-art grid — and the transparent per-widget background
/// override below is what silences the composite's built-in hover/press
/// fill (painting a fully transparent wash instead). Keyboard focus
/// still draws the standard ring, and the whole tile — art and text —
/// stays one hit target with the album-by-artist accessible label.
fn albumTile(ui: *Ui, fit: GridFit, cell: *const model_mod.AlbumCell) Ui.Node {
    const cover = fit.tile_width - tile_padding * 2;
    return ui.el(.list_item, .{
        // Height derives from width: the square cover plus the text
        // block and paddings, so tiles stay uniform as they grow
        // between column-count breakpoints.
        .height = tile_padding * 2 + cover + cover_text_gap + tile_text_height,
        .padding = tile_padding,
        // A widget-level background override recolors whatever state
        // fill the composite would paint; fully transparent, it removes
        // the hover and press washes without touching hit testing,
        // cursor intent, or the focus ring.
        .style = .{ .background = canvas.Color.rgba(0, 0, 0, 0) },
        .on_press = Msg{ .open_album = cell.id },
        .context_menu = &.{
            .{ .label = "Play Album", .msg = Msg{ .play_album = cell.id } },
            .{ .label = "Open Album", .msg = Msg{ .open_album = cell.id } },
        },
        .semantics = .{ .role = .listitem, .label = ui.fmt("{s} by {s}", .{ cell.title, cell.artist }) },
    }, .{
        // list_item flows children horizontally; the single grown column
        // carries the vertical cover-over-text stack.
        ui.column(.{ .gap = cover_text_gap, .grow = 1 }, .{
            ui.avatar(.{
                .image = cell.cover,
                .width = cover,
                .height = cover,
                .style = .{ .radius = 8 },
                .semantics = .{ .label = ui.fmt("{s} cover", .{cell.title}) },
            }, cell.initials),
            ui.row(.{ .gap = 8, .cross = .center }, .{
                ui.column(.{ .gap = 1, .grow = 1 }, .{
                    // One-line title/artist by design: elide behind a
                    // trailing ellipsis at the tile width, never wrap
                    // over the line below.
                    ui.text(.{ .wrap = false }, cell.title),
                    ui.text(.{ .size = .sm, .wrap = false, .style_tokens = .{ .foreground = .text_muted } }, cell.artist),
                }),
                if (cell.playing)
                    ui.el(.badge, .{ .variant = .primary, .text = "Playing" }, .{})
                else
                    ui.el(.stack, .{}, .{}),
            }),
        }),
    });
}

fn emptyState(ui: *Ui, model: *const Model) Ui.Node {
    return ui.panel(.{
        .padding = 24,
        .style_tokens = .{ .background = .surface, .radius = .lg, .border_color = .border },
        .semantics = .{ .label = "No albums match" },
    }, ui.column(.{ .gap = 6 }, .{
        ui.text(.{}, ui.fmt("No matches for \"{s}\"", .{model.search()})),
        ui.text(.{ .size = .sm, .style_tokens = .{ .foreground = .text_muted } }, "Try an album, artist, or song title."),
    }));
}

// ----------------------------------------------------------- album detail

fn albumDetailView(ui: *Ui, model: *const Model, album_id: u8) Ui.Node {
    const album = model_mod.albumById(album_id);
    const rows = model.albumTrackRows(ui.arena, album_id);
    return ui.scroll(.{
        .grow = 1,
        .value = model.detail_scroll,
        .on_scroll = Ui.scrollMsg(.detail_scrolled),
        .semantics = .{ .label = "Album detail" },
    }, ui.column(.{ .padding = content_padding, .gap = 18 }, .{
        ui.row(.{}, .{
            backButton(ui),
            ui.spacer(1),
        }),
        ui.row(.{ .gap = 20 }, .{
            ui.avatar(.{
                .image = model.coverFor(album.id),
                .width = detail_cover_size,
                .height = detail_cover_size,
                .style = .{ .radius = 10 },
                .semantics = .{ .label = ui.fmt("{s} cover", .{album.title}) },
            }, album.initials),
            ui.column(.{ .gap = 8, .grow = 1, .main = .end }, .{
                ui.text(.{ .size = .sm, .style_tokens = .{ .foreground = .text_muted } }, "Album"),
                AlbumTitleView.build(ui, model),
                ui.text(.{ .style_tokens = .{ .foreground = .text_muted } }, ui.fmt("{s} · {d} · {d} tracks", .{ album.artist, album.year, rows.len })),
                ui.row(.{ .gap = 8, .cross = .center }, .{
                    playAlbumButton(ui, album.id),
                    ui.spacer(1),
                }),
            }),
        }),
        trackList(ui, rows, "Album tracks"),
    }));
}

/// Icon+text buttons via `ElementOptions.icon`: the icon is part of the
/// button's own rendering, so each control is ONE widget — one hit
/// target, no duplicated on_press, and the icon follows the button's
/// enabled/disabled tint for free. (These replaced the old overlay-stack
/// idiom the moment icon-in-button landed.)
fn backButton(ui: *Ui) Ui.Node {
    return ui.button(.{
        .variant = .ghost,
        .size = .sm,
        .icon = "chevron-left",
        .on_press = .close_album,
        .semantics = .{ .label = "Back to albums" },
    }, "Back to albums");
}

fn playAlbumButton(ui: *Ui, album_id: u8) Ui.Node {
    return ui.button(.{
        .variant = .primary,
        .icon = "play",
        .on_press = Msg{ .play_album = album_id },
        .semantics = .{ .label = "Play album" },
    }, "Play album");
}

// ------------------------------------------------------------------ songs

fn songsView(ui: *Ui, model: *const Model) Ui.Node {
    const rows = model.visibleTracks(ui.arena);
    return ui.scroll(.{
        .grow = 1,
        .value = model.songs_scroll,
        .on_scroll = Ui.scrollMsg(.songs_scrolled),
        .semantics = .{ .label = "All songs" },
    }, ui.column(.{ .padding = content_padding, .gap = 18 }, .{
        sectionHeading(ui, "Songs", ui.fmt("{d} of {d}", .{ rows.len, model_mod.tracks.len })),
        if (rows.len == 0) emptyState(ui, model) else trackList(ui, rows, "Songs"),
    }));
}

// ------------------------------------------------------------- track rows

fn trackList(ui: *Ui, rows: []const model_mod.TrackRow, label: []const u8) Ui.Node {
    // Flat house rows: no inter-row gaps — the rows' washes are the only
    // separation.
    return ui.el(.list, .{
        .semantics = .{ .role = .list, .label = label },
    }, ui.each(rows, trackKey, trackRowView));
}

fn trackKey(row: *const model_mod.TrackRow) canvas.UiKey {
    return canvas.uiKey(row.id);
}

/// One pressable track row: a FLAT list row (the list_item composite —
/// no border, no card chrome; hover is a full-width wash), with custom
/// children flowing horizontally inside it. The gesture split is the
/// desktop list convention: a single click (or Space on a ring-focused
/// row) SELECTS, the double click (or Enter, via `on_submit`) PLAYS.
/// The selection wears the inverted register — accent fill under
/// window-background ink, stated per-widget through style tokens so the
/// unselected rows keep their neutral hover/press washes. The native
/// context menu is the Zig-only piece: right/ctrl-click presents the OS
/// menu and each item dispatches a typed Msg exactly like a press.
fn trackRowView(ui: *Ui, row: *const model_mod.TrackRow) Ui.Node {
    return ui.el(.list_item, .{
        .global_key = canvas.uiKey(@as(u32, row.id)),
        .height = 44,
        .padding = 10,
        .gap = 12,
        .cross = .center,
        .selected = row.selected,
        .style_tokens = if (row.selected) .{ .background = .accent } else .{},
        .on_press = Msg{ .select_track = row.id },
        .on_double_press = Msg{ .play_track = row.id },
        .on_submit = Msg{ .play_track = row.id },
        // Two items per row on purpose: the per-view context-menu budget is
        // 512 items (canvas_limits), and the all-songs list mounts every
        // catalog track as a row — two items per row keeps a comfortable
        // margin even as the manifest grows.
        .context_menu = &.{
            .{ .label = "Play Next", .msg = Msg{ .queue_track = row.id } },
            .{ .label = "Copy Title", .msg = Msg{ .copy_title = row.id } },
        },
        .semantics = .{ .role = .listitem, .label = row.title },
    }, .{
        trackIndicator(ui, row),
        if (row.subtitle.len == 0)
            ui.text(.{ .grow = 1, .style_tokens = rowTitleTokens(row) }, row.title)
        else
            ui.column(.{ .gap = 1, .grow = 1 }, .{
                ui.text(.{ .style_tokens = rowTitleTokens(row) }, row.title),
                ui.text(.{ .size = .sm, .style_tokens = rowMutedTokens(row) }, row.subtitle),
            }),
        if (row.queued)
            ui.el(.badge, .{ .variant = .secondary, .text = "Up next" }, .{})
        else
            ui.el(.stack, .{}, .{}),
        durationText(ui, row),
    });
}

/// Row title ink: window-background on the selected (accent) row — the
/// inverted register — accent on the loaded track's row, default
/// otherwise.
fn rowTitleTokens(row: *const model_mod.TrackRow) canvas.StyleTokenRefs {
    if (row.selected) return .{ .foreground = .background };
    if (row.now) return .{ .foreground = .accent };
    return .{};
}

/// Row secondary ink (subtitle, duration, track number): muted at rest,
/// window-background on the selected row — muted gray on the accent
/// fill would fail the contrast the inverted register exists to keep.
fn rowMutedTokens(row: *const model_mod.TrackRow) canvas.StyleTokenRefs {
    if (row.selected) return .{ .foreground = .background };
    return .{ .foreground = .text_muted };
}

/// The leading track-row slot: a STATE icon on the loaded track's row —
/// the pause glyph while audio is playing, the play glyph while it is
/// paused (the icon names the state, matching the transport button's
/// convention) — and the track number everywhere else. Icons are
/// decoration (never hit-tested), so the row's press handling is
/// untouched; the fixed 24px slot keeps the number column's alignment.
/// On the selected row the icon takes the inverted ink like the text —
/// an accent glyph would vanish into the accent fill.
fn trackIndicator(ui: *Ui, row: *const model_mod.TrackRow) Ui.Node {
    if (!row.now) {
        return ui.text(.{ .width = 24, .size = .sm, .style_tokens = rowMutedTokens(row) }, row.number);
    }
    const icon_tokens: canvas.StyleTokenRefs = if (row.selected)
        .{ .foreground = .background }
    else if (row.playing)
        .{ .foreground = .accent }
    else
        .{ .foreground = .text_muted };
    return ui.row(.{ .width = 24, .cross = .center }, .{
        if (row.playing)
            ui.icon(.{ .width = 14, .height = 14, .style_tokens = icon_tokens }, "pause")
        else
            ui.icon(.{ .width = 14, .height = 14, .style_tokens = icon_tokens }, "play"),
    });
}

/// Right-aligned fixed-width duration. The fixed width is a column: it
/// keeps every row's duration right edge aligned regardless of digit
/// count ("8:05" vs "12:41"), sized for the widest plausible value.
fn durationText(ui: *Ui, row: *const model_mod.TrackRow) Ui.Node {
    var node = ui.text(.{ .width = 44, .size = .sm, .style_tokens = rowMutedTokens(row) }, row.duration);
    node.widget.text_alignment = .end;
    return node;
}

// ---------------------------------------------------------------- shared

fn sectionHeading(ui: *Ui, title: []const u8, count: []const u8) Ui.Node {
    // Intrinsic width: layout measures with the bundled face's real
    // advances and the packet host draws the engine's lines verbatim,
    // so the old slack-width workaround (needed when the estimator
    // diverged from real glyph metrics) is gone.
    return ui.row(.{ .gap = 10, .cross = .center }, .{
        ui.paragraph(.{ .semantics = .{ .label = title } }, &.{
            .{ .text = title, .weight = .bold, .scale = 1.45 },
        }),
        ui.el(.badge, .{ .variant = .secondary, .text = count }, .{}),
        ui.spacer(1),
    });
}
