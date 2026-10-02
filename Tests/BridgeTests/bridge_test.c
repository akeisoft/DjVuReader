/*
 * Bridge self-test. Build and run with Scripts/test-bridge.sh.
 * Exercises every entry point of DjVuBridge against Tests/Fixtures/sample.djvu.
 */
#include "../../Sources/Engine/DjVuBridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond, ...)                                  \
    do {                                                  \
        if (cond) {                                       \
            printf("  ok    ");                           \
        } else {                                          \
            printf("  FAIL  ");                           \
            failures++;                                   \
        }                                                 \
        printf(__VA_ARGS__);                              \
        printf("\n");                                     \
    } while (0)

/* Pixel at (x, y) of a BGRA buffer as 0xRRGGBB. */
static unsigned rgb_at(const uint8_t *px, size_t row_bytes, int x, int y)
{
    const uint8_t *p = px + (size_t)y * row_bytes + (size_t)x * 4;
    return ((unsigned)p[2] << 16) | ((unsigned)p[1] << 8) | p[0];
}

static int count_dark(const uint8_t *px, size_t row_bytes, int w, int h)
{
    int n = 0;
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            const uint8_t *p = px + (size_t)y * row_bytes + (size_t)x * 4;
            if (p[0] < 100 && p[1] < 100 && p[2] < 100)
                n++;
        }
    return n;
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "Tests/Fixtures/sample.djvu";
    char err[256];

    if (argc > 2)
        djv_set_resource_dir(argv[2]); /* message catalogs, like the app does */
    printf("DjVuBridge test, ddjvuapi version %d\n", djv_api_version());

    /* Missing file must fail cleanly with a message. */
    djv_doc *missing = djv_open("/nonexistent/file.djvu", err, sizeof err);
    CHECK(missing == NULL && err[0], "missing file is rejected: \"%s\"", err);

    djv_doc *doc = djv_open(path, err, sizeof err);
    CHECK(doc != NULL, "open %s", path);
    if (!doc)
        return 1;

    int pages = djv_page_count(doc);
    CHECK(pages == 3, "page count = %d", pages);

    djv_page_info info;
    CHECK(djv_get_page_info(doc, 0, &info) == 0 && info.width == 1166 && info.height == 1654 &&
              info.dpi == 200 && info.rotation == 0,
          "page 1 info %dx%d @%d dpi, rotation %d", info.width, info.height, info.dpi, info.rotation);
    CHECK(djv_get_page_info(doc, 99, &info) != 0, "page 100 info is an error");

    /* Full page, downscaled to 583x827 (50 %). */
    int fw = 583, fh = 827;
    size_t rb = (size_t)fw * 4;
    uint8_t *buf = malloc(rb * (size_t)fh);
    int r = djv_render(doc, 0, DJV_MODE_COLOR, fw, fh, 0, 0, fw, fh, buf, rb);
    CHECK(r == 0, "render page 1 at 50%% -> %d", r);
    CHECK(buf[3] == 0xFF, "alpha byte is opaque (0x%02X)", buf[3]);
    CHECK(rgb_at(buf, rb, 5, 5) == 0xFFFFFF, "corner is white (0x%06X)", rgb_at(buf, rb, 5, 5));
    int dark = count_dark(buf, rb, fw, fh);
    CHECK(dark > 2000, "text pixels present (%d dark pixels)", dark);

    /* A tile from the middle of the same scaled page must equal the matching
       part of the full render. */
    int tx = 40, ty = 50, tw = 200, th = 60;
    size_t trb = (size_t)tw * 4;
    uint8_t *tile = malloc(trb * (size_t)th);
    r = djv_render(doc, 0, DJV_MODE_COLOR, fw, fh, tx, ty, tw, th, tile, trb);
    int same = 1;
    for (int y = 0; y < th && same; y++)
        if (memcmp(tile + (size_t)y * trb, buf + (size_t)(y + ty) * rb + (size_t)tx * 4, trb) != 0)
            same = 0;
    CHECK(r == 0 && same, "tile render matches the full render");

    /* A region hanging off the bottom-right edge is clipped, outside is white. */
    r = djv_render(doc, 0, DJV_MODE_COLOR, fw, fh, fw - 100, fh - 30, tw, th, tile, trb);
    CHECK(r == 0 && rgb_at(tile, trb, tw - 1, th - 1) == 0xFFFFFF, "edge tile is clipped -> %d", r);

    /* Color page: the gradient background must not be white. */
    r = djv_render(doc, 1, DJV_MODE_COLOR, fw, fh, 0, 0, fw, fh, buf, rb);
    unsigned bg = rgb_at(buf, rb, fw - 10, fh - 10);
    CHECK(r == 0 && bg != 0xFFFFFF, "color page background 0x%06X", bg);

    /* Black & white mode on a bitonal page renders the mask. */
    r = djv_render(doc, 2, DJV_MODE_BLACK, fw, fh, 0, 0, fw, fh, buf, rb);
    CHECK(r == 0 && count_dark(buf, rb, fw, fh) > 1000, "black&white mode on page 3 -> %d", r);

    /* Thumbnail fits into 128x128 and keeps the aspect ratio. */
    int tbw = 128, tbh = 128;
    uint8_t *thumb = malloc(128 * 128 * 4);
    r = djv_render_thumbnail(doc, 1, &tbw, &tbh, thumb, 128 * 4);
    CHECK(r == 0 && tbw <= 128 && tbh == 128 && tbw > 80 && tbw < 95,
          "thumbnail of page 2 is %dx%d", tbw, tbh);

    /* Text layer. */
    djv_text *text = djv_get_text(doc, 0);
    CHECK(text != NULL, "page 1 has a text layer");
    if (text) {
        printf("        text: %.*s\n", (int)text->utf8_length, text->utf8);
        CHECK(strstr(text->utf8, "ґанок,") != NULL, "Ukrainian letters survive (ґанок)");
        CHECK(strstr(text->utf8, "Вступ\n") != NULL, "line break after the heading");
        CHECK(text->word_count == 15, "word count = %d", text->word_count);
        djv_word w = text->words[0];
        CHECK(w.x0 == 100 && w.y0 > 100 && w.y0 < 200 && w.x1 > w.x0 && w.y1 > w.y0,
              "first word box (%d,%d)-(%d,%d), top-left origin", w.x0, w.y0, w.x1, w.y1);
        CHECK(strncmp(text->utf8 + w.offset, "Розділ", (size_t)w.length) == 0,
              "first word is \"%.*s\"", w.length, text->utf8 + w.offset);
        djv_word last = text->words[text->word_count - 1];
        CHECK(last.line == 3, "last word is on line index %d", last.line);
        CHECK(text->page_width == 1166 && text->page_height == 1654, "text coordinate space %dx%d",
              text->page_width, text->page_height);
        djv_free_text(text);
    }

    /* Outline. */
    int n = 0;
    djv_outline_item *outline = djv_get_outline(doc, &n);
    CHECK(outline != NULL && n == 4, "outline has %d entries", n);
    for (int i = 0; outline && i < n; i++)
        printf("        %*s%s -> page %d\n", outline[i].depth * 2, "", outline[i].title, outline[i].page + 1);
    if (outline && n == 4) {
        CHECK(!strcmp(outline[0].title, "Розділ 1. Вступ") && outline[0].page == 0, "entry 1 -> page 1");
        CHECK(outline[2].depth == 1 && outline[2].page == 1, "nested entry -> page 2, depth 1");
        CHECK(outline[3].page == 2, "last entry -> page 3");
    }
    djv_free_outline(outline, n);

    /* Page titles. */
    char *title = djv_copy_page_title(doc, 2);
    CHECK(title && !strcmp(title, "iii"), "page 3 title \"%s\"", title ? title : "(null)");
    free(title);
    title = djv_copy_page_title(doc, 0);
    CHECK(title == NULL, "page 1 has no title of its own");
    free(title);

    char *titles[3];
    int found = djv_copy_page_titles(doc, titles, 3);
    CHECK(found == 1 && titles[0] == NULL && titles[1] == NULL && titles[2] && !strcmp(titles[2], "iii"),
          "batch page titles: %d found", found);
    for (int i = 0; i < 3; i++)
        free(titles[i]);

    free(thumb);
    free(tile);
    free(buf);
    djv_close(doc);

    printf(failures ? "\n%d check(s) FAILED\n" : "\nall checks passed\n", failures);
    return failures ? 1 : 0;
}
