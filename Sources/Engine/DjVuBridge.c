/*
 * DjVuBridge.c — see DjVuBridge.h for the contract.
 * Licensed under GPL-2.0-or-later, like DjVuLibre it links against.
 */
/* setenv() under strict C modes in Linux test builds. */
#if defined(__linux__) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include "DjVuBridge.h"

#include <libdjvu/ddjvuapi.h>
#include <libdjvu/miniexp.h>

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Decoded pages kept alive so that tiles of the same page at different zoom
   levels do not decode the page again. A decoded page holds compressed layers,
   not a bitmap, so a handful of them is cheap. */
#define PAGE_CACHE_SLOTS 6

/* DjVuLibre's own cache of decoded data, per document. */
#define DJVU_CACHE_BYTES (64UL * 1024UL * 1024UL)

/* Pages that failed to decode. A damaged page is asked for once per tile;
   without this list every tile would decode it again, holding the document
   lock and stalling the other pages. */
#define FAILED_SLOTS 16

typedef struct {
    int pageno;
    ddjvu_page_t *page;
    unsigned long stamp;
} page_slot;

struct djv_doc {
    ddjvu_context_t *ctx;
    ddjvu_document_t *doc;
    ddjvu_format_t *format;
    page_slot cache[PAGE_CACHE_SLOTS];
    unsigned long clock;
    int failed[FAILED_SLOTS];
    int failed_next;
    char error[512];
};

/* ------------------------------------------------------------------ messages */

/* Drains the message queue; with wait != 0 blocks until at least one message
   arrives. Errors are remembered for djv_last_error. */
static void pump(djv_doc *d, int wait)
{
    const ddjvu_message_t *msg;
    if (wait)
        ddjvu_message_wait(d->ctx);
    while ((msg = ddjvu_message_peek(d->ctx))) {
        if (msg->m_any.tag == DDJVU_ERROR && msg->m_error.message) {
            const char *text = msg->m_error.message;
            /* DjVuLibre prefixes messages with an id like "[1-11711] ". */
            if (text[0] == '[') {
                const char *end = strstr(text, "] ");
                if (end)
                    text = end + 2;
            }
            snprintf(d->error, sizeof d->error, "%s", text);
        }
        ddjvu_message_pop(d->ctx);
    }
}

/* ------------------------------------------------------------------ helpers */

static void fill_white(uint8_t *pixels, int width, int height, size_t row_bytes)
{
    for (int y = 0; y < height; y++)
        memset(pixels + (size_t)y * row_bytes, 0xFF, (size_t)width * 4);
}

static ddjvu_render_mode_t render_mode(int mode)
{
    switch (mode) {
    case DJV_MODE_BLACK:      return DDJVU_RENDER_BLACK;
    case DJV_MODE_BACKGROUND: return DDJVU_RENDER_BACKGROUND;
    case DJV_MODE_FOREGROUND: return DDJVU_RENDER_FOREGROUND;
    default:                  return DDJVU_RENDER_COLOR;
    }
}

static char *dup_string(const char *s)
{
    size_t n = s ? strlen(s) : 0;
    char *copy = malloc(n + 1);
    if (!copy)
        return NULL;
    if (n)
        memcpy(copy, s, n);
    copy[n] = 0;
    return copy;
}

static int failed_before(const djv_doc *d, int pageno)
{
    for (int i = 0; i < FAILED_SLOTS; i++)
        if (d->failed[i] == pageno)
            return 1;
    return 0;
}

static void remember_failure(djv_doc *d, int pageno)
{
    d->failed[d->failed_next] = pageno;
    d->failed_next = (d->failed_next + 1) % FAILED_SLOTS;
}

/* Returns a decoded page from the small LRU cache, decoding it when needed. */
static ddjvu_page_t *acquire_page(djv_doc *d, int pageno)
{
    int slot = 0;
    unsigned long oldest = ULONG_MAX;

    if (failed_before(d, pageno))
        return NULL;

    for (int i = 0; i < PAGE_CACHE_SLOTS; i++) {
        if (d->cache[i].page && d->cache[i].pageno == pageno) {
            d->cache[i].stamp = ++d->clock;
            return d->cache[i].page;
        }
    }
    for (int i = 0; i < PAGE_CACHE_SLOTS; i++) {
        if (!d->cache[i].page) {
            slot = i;
            break;
        }
        if (d->cache[i].stamp < oldest) {
            oldest = d->cache[i].stamp;
            slot = i;
        }
    }
    if (d->cache[slot].page) {
        ddjvu_page_release(d->cache[slot].page);
        d->cache[slot].page = NULL;
        d->cache[slot].pageno = -1;
    }

    ddjvu_page_t *page = ddjvu_page_create_by_pageno(d->doc, pageno);
    if (!page) {
        remember_failure(d, pageno);
        return NULL;
    }
    while (!ddjvu_page_decoding_done(page))
        pump(d, 1);
    if (ddjvu_page_decoding_error(page)) {
        ddjvu_page_release(page);
        remember_failure(d, pageno);
        return NULL;
    }
    d->cache[slot].page = page;
    d->cache[slot].pageno = pageno;
    d->cache[slot].stamp = ++d->clock;
    return page;
}

/* ------------------------------------------------------------------ document */

djv_doc *djv_open(const char *utf8_path, char *errbuf, size_t errbuf_size)
{
    djv_doc *d = calloc(1, sizeof *d);
    if (!d) {
        if (errbuf && errbuf_size)
            snprintf(errbuf, errbuf_size, "out of memory");
        return NULL;
    }
    for (int i = 0; i < PAGE_CACHE_SLOTS; i++)
        d->cache[i].pageno = -1;
    for (int i = 0; i < FAILED_SLOTS; i++)
        d->failed[i] = -1;

    d->ctx = ddjvu_context_create("DjVuReader");
    if (!d->ctx)
        goto fail;
    ddjvu_cache_set_size(d->ctx, DJVU_CACHE_BYTES);

    d->doc = ddjvu_document_create_by_filename_utf8(d->ctx, utf8_path, 1);
    if (!d->doc)
        goto fail;
    while (!ddjvu_document_decoding_done(d->doc))
        pump(d, 1);
    if (ddjvu_document_decoding_error(d->doc))
        goto fail;
    pump(d, 0);

    /* 0xAARRGGBB words; the fourth value is xored in, which sets alpha to 0xFF. */
    unsigned int masks[4] = { 0x00FF0000u, 0x0000FF00u, 0x000000FFu, 0xFF000000u };
    d->format = ddjvu_format_create(DDJVU_FORMAT_RGBMASK32, 4, masks);
    if (!d->format)
        goto fail;
    ddjvu_format_set_row_order(d->format, 1);   /* rows top to bottom */
    ddjvu_format_set_y_direction(d->format, 1); /* y measured from the top */
    return d;

fail:
    if (d->ctx)
        pump(d, 0); /* collect the reason DjVuLibre reported, if any */
    if (errbuf && errbuf_size)
        snprintf(errbuf, errbuf_size, "%s",
                 d->error[0] ? d->error : "the file is not a readable DjVu document");
    djv_close(d);
    return NULL;
}

void djv_close(djv_doc *d)
{
    if (!d)
        return;
    for (int i = 0; i < PAGE_CACHE_SLOTS; i++)
        if (d->cache[i].page)
            ddjvu_page_release(d->cache[i].page);
    if (d->format)
        ddjvu_format_release(d->format);
    if (d->doc)
        ddjvu_document_release(d->doc);
    if (d->ctx)
        ddjvu_context_release(d->ctx);
    free(d);
}

int djv_page_count(djv_doc *d)
{
    return d ? ddjvu_document_get_pagenum(d->doc) : 0;
}

int djv_get_page_info(djv_doc *d, int page, djv_page_info *info)
{
    ddjvu_pageinfo_t pi;
    ddjvu_status_t r;

    if (!d || !info)
        return -1;
    while ((r = ddjvu_document_get_pageinfo(d->doc, page, &pi)) < DDJVU_JOB_OK)
        pump(d, 1);
    if (r >= DDJVU_JOB_FAILED)
        return -1;
    info->width = pi.width;
    info->height = pi.height;
    info->dpi = pi.dpi;
    info->rotation = pi.rotation;
    return 0;
}

const char *djv_last_error(djv_doc *d)
{
    return d ? d->error : "";
}

int djv_api_version(void)
{
    return ddjvu_code_get_version();
}

/* ------------------------------------------------------------------ rendering */

int djv_render(djv_doc *d, int pageno, int mode,
               int full_width, int full_height,
               int x, int y, int width, int height,
               uint8_t *pixels, size_t row_bytes)
{
    if (!d || !pixels || width <= 0 || height <= 0 || full_width <= 0 || full_height <= 0)
        return -1;

    ddjvu_page_t *page = acquire_page(d, pageno);
    if (!page) {
        fill_white(pixels, width, height, row_bytes);
        return -1;
    }

    /* Clip the requested region to the page; the parts outside stay white. */
    int rx = x < 0 ? 0 : x;
    int ry = y < 0 ? 0 : y;
    int rr = x + width > full_width ? full_width : x + width;
    int rb = y + height > full_height ? full_height : y + height;
    if (rr <= rx || rb <= ry) {
        fill_white(pixels, width, height, row_bytes);
        return 1;
    }
    if (rx != x || ry != y || rr - rx != width || rb - ry != height)
        fill_white(pixels, width, height, row_bytes);

    ddjvu_rect_t prect = { 0, 0, (unsigned int)full_width, (unsigned int)full_height };
    ddjvu_rect_t rrect = { rx, ry, (unsigned int)(rr - rx), (unsigned int)(rb - ry) };
    uint8_t *origin = pixels + (size_t)(ry - y) * row_bytes + (size_t)(rx - x) * 4;

    if (!ddjvu_page_render(page, render_mode(mode), &prect, &rrect,
                           d->format, (unsigned long)row_bytes, (char *)origin)) {
        fill_white(pixels, width, height, row_bytes);
        return 1;
    }
    return 0;
}

int djv_render_thumbnail(djv_doc *d, int pageno, int *width, int *height,
                         uint8_t *pixels, size_t row_bytes)
{
    ddjvu_status_t r;

    if (!d || !width || !height || !pixels || *width <= 0 || *height <= 0)
        return -1;
    r = ddjvu_thumbnail_status(d->doc, pageno, 1);
    while (r < DDJVU_JOB_OK) {
        pump(d, 1);
        r = ddjvu_thumbnail_status(d->doc, pageno, 0);
    }
    if (r >= DDJVU_JOB_FAILED)
        return -1;
    if (!ddjvu_thumbnail_render(d->doc, pageno, width, height,
                                d->format, (unsigned long)row_bytes, (char *)pixels))
        return -1;
    return 0;
}

/* ------------------------------------------------------------------ text layer */

typedef struct {
    char *buf;
    size_t len, cap;
    djv_word *words;
    int count, cap_words;
    int line;
    int pending_newline;
    int page_width, page_height;
    int failed;
} text_builder;

static int tb_reserve(text_builder *b, size_t extra)
{
    if (b->len + extra + 1 <= b->cap)
        return 1;
    size_t cap = b->cap ? b->cap : 1024;
    while (cap < b->len + extra + 1)
        cap *= 2;
    char *buf = realloc(b->buf, cap);
    if (!buf)
        return 0;
    b->buf = buf;
    b->cap = cap;
    return 1;
}

static void tb_add_word(text_builder *b, const char *s, const int c[4])
{
    size_t n = strlen(s);
    if (b->failed || n == 0)
        return;
    if (!tb_reserve(b, n + 1)) {
        b->failed = 1;
        return;
    }
    if (b->len > 0)
        b->buf[b->len++] = b->pending_newline ? '\n' : ' ';
    b->pending_newline = 0;

    if (b->count == b->cap_words) {
        int cap = b->cap_words ? b->cap_words * 2 : 256;
        djv_word *words = realloc(b->words, (size_t)cap * sizeof *words);
        if (!words) {
            b->failed = 1;
            return;
        }
        b->words = words;
        b->cap_words = cap;
    }
    djv_word *w = &b->words[b->count++];
    /* DjVu text boxes are (xmin ymin xmax ymax) with y growing upwards. */
    w->x0 = c[0];
    w->x1 = c[2];
    w->y0 = b->page_height - c[3];
    w->y1 = b->page_height - c[1];
    w->offset = (int)b->len;
    w->length = (int)n;
    w->line = b->line;

    memcpy(b->buf + b->len, s, n);
    b->len += n;
    b->buf[b->len] = 0;
}

static void tb_walk(text_builder *b, miniexp_t node, int depth)
{
    if (b->failed || depth > 32 || !miniexp_consp(node))
        return;
    miniexp_t type = miniexp_car(node);
    if (!miniexp_symbolp(type))
        return;
    const char *name = miniexp_to_name(type);

    miniexp_t rest = miniexp_cdr(node);
    int c[4];
    for (int i = 0; i < 4; i++) {
        miniexp_t v = miniexp_car(rest);
        if (!miniexp_numberp(v))
            return;
        c[i] = miniexp_to_int(v);
        rest = miniexp_cdr(rest);
    }
    if (depth == 0) {
        b->page_width = c[2];
        b->page_height = c[3];
    }

    miniexp_t first = miniexp_car(rest);
    if (miniexp_stringp(first)) {
        tb_add_word(b, miniexp_to_str(first), c);
    } else {
        for (; miniexp_consp(rest); rest = miniexp_cdr(rest))
            tb_walk(b, miniexp_car(rest), depth + 1);
    }

    /* Anything at line level or above ends a line. */
    if (name && (!strcmp(name, "line") || !strcmp(name, "para") ||
                 !strcmp(name, "region") || !strcmp(name, "column"))) {
        if (b->count > 0 && !b->pending_newline) {
            b->pending_newline = 1;
            b->line++;
        }
    }
}

djv_text *djv_get_text(djv_doc *d, int page)
{
    miniexp_t r;

    if (!d)
        return NULL;
    while ((r = ddjvu_document_get_pagetext(d->doc, page, "word")) == miniexp_dummy)
        pump(d, 1);
    if (!miniexp_consp(r)) {
        if (r != miniexp_nil)
            ddjvu_miniexp_release(d->doc, r);
        return NULL;
    }

    text_builder b;
    memset(&b, 0, sizeof b);
    tb_walk(&b, r, 0);
    ddjvu_miniexp_release(d->doc, r);

    if (b.failed || b.count == 0) {
        free(b.buf);
        free(b.words);
        return NULL;
    }
    djv_text *t = calloc(1, sizeof *t);
    if (!t) {
        free(b.buf);
        free(b.words);
        return NULL;
    }
    t->utf8 = b.buf;
    t->utf8_length = b.len;
    t->words = b.words;
    t->word_count = b.count;
    t->page_width = b.page_width;
    t->page_height = b.page_height;
    return t;
}

void djv_free_text(djv_text *t)
{
    if (!t)
        return;
    free(t->utf8);
    free(t->words);
    free(t);
}

/* ------------------------------------------------------------------ outline */

typedef struct {
    djv_outline_item *items;
    int count, cap;
    int failed;
} outline_builder;

static int all_digits(const char *s)
{
    if (!*s)
        return 0;
    for (; *s; s++)
        if (*s < '0' || *s > '9')
            return 0;
    return 1;
}

/* Finds the page whose file id, name or title equals key. */
static int page_by_name(djv_doc *d, const char *key)
{
    int files = ddjvu_document_get_filenum(d->doc);
    for (int f = 0; f < files; f++) {
        ddjvu_fileinfo_t fi;
        ddjvu_status_t r;
        while ((r = ddjvu_document_get_fileinfo(d->doc, f, &fi)) < DDJVU_JOB_OK)
            pump(d, 1);
        if (r >= DDJVU_JOB_FAILED || fi.type != 'P' || fi.pageno < 0)
            continue;
        if ((fi.id && !strcmp(fi.id, key)) ||
            (fi.name && !strcmp(fi.name, key)) ||
            (fi.title && !strcmp(fi.title, key)))
            return fi.pageno;
    }
    return -1;
}

/* "#12" is page 12 (1-based); "#name" is a page file id or title. */
static int resolve_link(djv_doc *d, const char *url)
{
    if (!url || url[0] != '#')
        return -1;
    const char *key = url + 1;
    if (all_digits(key)) {
        long n = strtol(key, NULL, 10);
        int pages = ddjvu_document_get_pagenum(d->doc);
        return (n >= 1 && n <= pages) ? (int)n - 1 : -1;
    }
    return page_by_name(d, key);
}

static void ob_push(outline_builder *ob, const char *title, int page, int depth)
{
    if (ob->failed)
        return;
    if (ob->count == ob->cap) {
        int cap = ob->cap ? ob->cap * 2 : 64;
        djv_outline_item *items = realloc(ob->items, (size_t)cap * sizeof *items);
        if (!items) {
            ob->failed = 1;
            return;
        }
        ob->items = items;
        ob->cap = cap;
    }
    char *copy = dup_string(title);
    if (!copy) {
        ob->failed = 1;
        return;
    }
    ob->items[ob->count].title = copy;
    ob->items[ob->count].page = page;
    ob->items[ob->count].depth = depth;
    ob->count++;
}

static void ob_walk(djv_doc *d, outline_builder *ob, miniexp_t list, int depth)
{
    if (depth > 32)
        return;
    for (; miniexp_consp(list); list = miniexp_cdr(list)) {
        miniexp_t item = miniexp_car(list);
        if (!miniexp_consp(item))
            continue;
        miniexp_t t = miniexp_car(item);
        miniexp_t u = miniexp_cadr(item);
        const char *title = miniexp_stringp(t) ? miniexp_to_str(t) : "";
        const char *url = miniexp_stringp(u) ? miniexp_to_str(u) : "";
        ob_push(ob, title, resolve_link(d, url), depth);
        ob_walk(d, ob, miniexp_cddr(item), depth + 1);
    }
}

djv_outline_item *djv_get_outline(djv_doc *d, int *count)
{
    miniexp_t r;

    if (count)
        *count = 0;
    if (!d || !count)
        return NULL;
    while ((r = ddjvu_document_get_outline(d->doc)) == miniexp_dummy)
        pump(d, 1);
    if (!miniexp_consp(r)) {
        if (r != miniexp_nil)
            ddjvu_miniexp_release(d->doc, r);
        return NULL;
    }

    outline_builder ob;
    memset(&ob, 0, sizeof ob);
    miniexp_t head = miniexp_car(r);
    if (miniexp_symbolp(head) && !strcmp(miniexp_to_name(head), "bookmarks"))
        ob_walk(d, &ob, miniexp_cdr(r), 0);
    ddjvu_miniexp_release(d->doc, r);

    if (ob.failed || ob.count == 0) {
        djv_free_outline(ob.items, ob.count);
        return NULL;
    }
    *count = ob.count;
    return ob.items;
}

void djv_free_outline(djv_outline_item *items, int count)
{
    if (!items)
        return;
    for (int i = 0; i < count; i++)
        free(items[i].title);
    free(items);
}

/* ------------------------------------------------------------------ page titles */

static int real_title(const ddjvu_fileinfo_t *fi);

char *djv_copy_page_title(djv_doc *d, int page)
{
    if (!d)
        return NULL;
    int files = ddjvu_document_get_filenum(d->doc);
    for (int f = 0; f < files; f++) {
        ddjvu_fileinfo_t fi;
        ddjvu_status_t r;
        while ((r = ddjvu_document_get_fileinfo(d->doc, f, &fi)) < DDJVU_JOB_OK)
            pump(d, 1);
        if (r >= DDJVU_JOB_FAILED || fi.type != 'P' || fi.pageno != page)
            continue;
        return real_title(&fi) ? dup_string(fi.title) : NULL;
    }
    return NULL;
}

/* A title equal to the file id is not a real title. */
static int real_title(const ddjvu_fileinfo_t *fi)
{
    return fi->title && fi->title[0] && !(fi->id && !strcmp(fi->title, fi->id));
}

int djv_copy_page_titles(djv_doc *d, char **titles, int count)
{
    int found = 0;
    if (!d || !titles || count <= 0)
        return 0;
    memset(titles, 0, (size_t)count * sizeof *titles);
    int files = ddjvu_document_get_filenum(d->doc);
    for (int f = 0; f < files; f++) {
        ddjvu_fileinfo_t fi;
        ddjvu_status_t r;
        while ((r = ddjvu_document_get_fileinfo(d->doc, f, &fi)) < DDJVU_JOB_OK)
            pump(d, 1);
        if (r >= DDJVU_JOB_FAILED || fi.type != 'P' || fi.pageno < 0 || fi.pageno >= count)
            continue;
        if (real_title(&fi) && !titles[fi.pageno]) {
            titles[fi.pageno] = dup_string(fi.title);
            if (titles[fi.pageno])
                found++;
        }
    }
    return found;
}

/* ------------------------------------------------------------------ resources */

void djv_set_resource_dir(const char *utf8_path)
{
    if (utf8_path && utf8_path[0])
        setenv("DJVU_CONFIG_DIR", utf8_path, 1);
}
