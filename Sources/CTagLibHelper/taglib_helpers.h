#ifndef TAGLIB_HELPERS_H
#define TAGLIB_HELPERS_H

/*
 * Thin C shim around TagLib's complex-property (picture) API.
 *
 * Swift cannot expand the `TAGLIB_COMPLEX_PROPERTY_PICTURE` macro directly —
 * these helpers wrap the macro + `taglib_complex_property_set` call.
 *
 * The file parameter is typed as `void*` here so the header doesn't depend on
 * TagLib's own headers (which would conflict with the CTagLib system module's
 * definition of `TagLib_File` if both were imported by Swift). Swift callers
 * pass their `OpaquePointer` from `taglib_file_new` through with a cast.
 *
 * The other text-tag setters (title/artist/…) don't need a shim because
 * Swift imports `tag_c.h` via the CTagLib module and can call them directly.
 */

#ifdef __cplusplus
extern "C" {
#endif

/** Replace all embedded pictures with a single front-cover image.
 *  \a file   TagLib_File* (opaque — pass the pointer from taglib_file_new)
 *  \a data   raw JPEG or PNG bytes
 *  \a size   byte count
 *  \a mime   "image/jpeg" or "image/png"
 *  Returns non-zero on success. */
int taglib_helper_set_picture(void *file,
                              const char *data,
                              unsigned int size,
                              const char *mime);

/** Remove all embedded pictures from the file. */
void taglib_helper_remove_pictures(void *file);

/** Read the first embedded picture from the file.
 *  Returns a malloc'd copy of the raw bytes and sets *out_size.
 *  Caller must free() the returned pointer.
 *  Returns NULL if no picture is found. */
unsigned char *taglib_helper_read_picture(void *file, unsigned int *out_size);

/** Read the ALBUMARTIST property (cross-format: Xiph ALBUMARTIST / ID3v2 TPE2 / MP4 aART).
 *  Returns a malloc'd C string the caller must free(), or NULL if unset. */
char *taglib_helper_get_album_artist(void *file);

/** Write the ALBUMARTIST property. Pass NULL value to leave unchanged; pass
 *  empty string ("") to clear the tag. */
void taglib_helper_set_album_artist(void *file, const char *value);

/** Read the COMPILATION property (Xiph COMPILATION / ID3v2 TCMP / MP4 cpil).
 *  Returns 1 when the tag is present and equal to "1", 0 otherwise. */
int taglib_helper_get_compilation(void *file);

/** Write the COMPILATION property. Non-zero `value` writes "1"; zero clears
 *  the tag entirely. */
void taglib_helper_set_compilation(void *file, int value);

#ifdef __cplusplus
}
#endif

#endif /* TAGLIB_HELPERS_H */
