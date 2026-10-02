/*
 * DjVuBridge — a thin, synchronous C layer over DjVuLibre's ddjvuapi.
 *
 * Every call blocks until the requested job is finished: it pumps the
 * document's own message queue (one ddjvu context per document), so the
 * Swift side never deals with DjVuLibre messages.
 *
 * Not thread-safe by itself. The Swift wrapper (DjVuDocument) serializes
 * all calls for one djv_doc with a lock; different djv_doc instances are
 * independent and may be used from different threads at the same time.
 *
 * Pixel format of every rendered buffer: 32 bits per pixel, little-endian
 * 0xAARRGGBB words (B, G, R, A in memory), alpha always 0xFF, rows top-down.
 * In CoreGraphics terms: byteOrder32Little | noneSkipFirst.
 *
 * Coordinates returned to the caller (text boxes, links) use page pixels
 * with the origin in the TOP-LEFT corner, like the rendered images.
 */
#ifndef DJVU_BRIDGE_H
#define DJVU_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct djv_doc djv_doc;

typedef struct {
    int width;      /* pixels, already swapped for the initial rotation */
    int height;     /* pixels, already swapped for the initial rotation */
    int dpi;        /* as stored in the file; may be 0 or bogus in old files */
    int rotation;   /* initial orientation: 0..3, multiples of 90 degrees */
} djv_page_info;

/* Render modes. Values are stable: they are stored in user settings. */
enum {
    DJV_MODE_COLOR = 0,       /* the whole page */
    DJV_MODE_BLACK = 1,       /* bitonal mask only (sharp text); color page when there is no mask */
    DJV_MODE_BACKGROUND = 2,  /* background layer only */
    DJV_MODE_FOREGROUND = 3   /* foreground layer only */
};

typedef struct {
    int x0, y0, x1, y1;  /* box in unrotated page pixels, origin top-left */
    int offset;          /* byte offset of the word inside djv_text.utf8 */
    int length;          /* byte length of the word */
    int line;            /* running line index on the page */
} djv_word;

typedef struct {
    char *utf8;          /* the page text: words separated by ' ', lines by '\n' */
    size_t utf8_length;
    djv_word *words;
    int word_count;
    int page_width;      /* coordinate space of the boxes (unrotated page) */
    int page_height;
} djv_text;

typedef struct {
    char *title;         /* UTF-8, never NULL */
    int page;            /* 0-based target page, -1 when the link is external or unresolved */
    int depth;           /* 0 for top-level entries */
} djv_outline_item;

/* Opens a bundled or indirect DjVu document. On failure returns NULL and,
   when errbuf is not NULL, writes a human-readable reason into it. */
djv_doc *djv_open(const char *utf8_path, char *errbuf, size_t errbuf_size);
void djv_close(djv_doc *doc);

int djv_page_count(djv_doc *doc);

/* Returns 0 on success, -1 when the page cannot be read. */
int djv_get_page_info(djv_doc *doc, int page, djv_page_info *info);

/* Renders the region (x, y, width, height) of the page scaled to
   full_width x full_height pixels. The region is clipped to the page.
   Returns 0 when pixels were rendered, 1 when the page has nothing to show
   in this mode (buffer filled with white), -1 on error (buffer filled with
   white). */
int djv_render(djv_doc *doc, int page, int mode,
               int full_width, int full_height,
               int x, int y, int width, int height,
               uint8_t *pixels, size_t row_bytes);

/* Renders a thumbnail that fits into *width x *height. On success returns 0
   and updates *width and *height to the real thumbnail size. The buffer must
   hold the requested (maximum) size. Returns -1 on failure. */
int djv_render_thumbnail(djv_doc *doc, int page, int *width, int *height,
                         uint8_t *pixels, size_t row_bytes);

/* Hidden text layer of a page at word granularity. Returns NULL when the
   page has no text layer. Free with djv_free_text. */
djv_text *djv_get_text(djv_doc *doc, int page);
void djv_free_text(djv_text *text);

/* Document outline (table of contents), flattened in display order with a
   depth for every entry. Returns NULL with *count == 0 when there is none.
   Free with djv_free_outline. */
djv_outline_item *djv_get_outline(djv_doc *doc, int *count);
void djv_free_outline(djv_outline_item *items, int count);

/* Page title stored in the document (for example "iv" or "Cover"); NULL when
   the page has no title of its own. Free with free(). */
char *djv_copy_page_title(djv_doc *doc, int page);

/* All page titles in one pass: titles[i] receives a malloc'ed title or NULL.
   The array must hold `count` pointers. Returns how many titles were found. */
int djv_copy_page_titles(djv_doc *doc, char **titles, int count);

/* Folder with DjVuLibre's message catalogs (the "osi" folder shipped inside
   the app bundle). Call once at launch, before opening any document. */
void djv_set_resource_dir(const char *utf8_path);

/* Last DjVuLibre error message for this document, or an empty string. */
const char *djv_last_error(djv_doc *doc);

/* DjVuLibre API version (ddjvuapi), for the About window. */
int djv_api_version(void);

#ifdef __cplusplus
}
#endif

#endif /* DJVU_BRIDGE_H */
