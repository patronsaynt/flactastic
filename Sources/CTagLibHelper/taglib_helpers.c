#include "taglib_helpers.h"
#include <taglib/tag_c.h>
#include <stdlib.h>
#include <string.h>

int taglib_helper_set_picture(void *file,
                              const char *data,
                              unsigned int size,
                              const char *mime) {
    if (!file || !data || size == 0 || !mime) return 0;
    TAGLIB_COMPLEX_PROPERTY_PICTURE(props, data, size, "", mime, "Front Cover");
    return taglib_complex_property_set((TagLib_File *)file, "PICTURE", props);
}

void taglib_helper_remove_pictures(void *file) {
    if (!file) return;
    taglib_complex_property_set((TagLib_File *)file, "PICTURE", NULL);
}

char *taglib_helper_get_album_artist(void *file) {
    if (!file) return NULL;
    char **values = taglib_property_get((TagLib_File *)file, "ALBUMARTIST");
    if (!values) return NULL;
    char *result = NULL;
    if (values[0] && values[0][0] != '\0') {
        size_t n = strlen(values[0]);
        result = (char *)malloc(n + 1);
        if (result) memcpy(result, values[0], n + 1);
    }
    taglib_property_free(values);
    return result;
}

void taglib_helper_set_album_artist(void *file, const char *value) {
    if (!file || !value) return;
    taglib_property_set((TagLib_File *)file, "ALBUMARTIST", value);
}

unsigned char *taglib_helper_read_picture(void *file, unsigned int *out_size) {
    if (!file || !out_size) return NULL;
    *out_size = 0;

    TagLib_Complex_Property_Attribute ***props =
        taglib_complex_property_get((TagLib_File *)file, "PICTURE");
    if (!props) return NULL;

    unsigned char *result = NULL;
    for (int i = 0; props[i] != NULL; i++) {
        for (int j = 0; props[i][j] != NULL; j++) {
            TagLib_Complex_Property_Attribute *attr = props[i][j];
            if (strcmp(attr->key, "data") == 0 &&
                attr->value.type == TagLib_Variant_ByteVector &&
                attr->value.size > 0) {
                result = (unsigned char *)malloc(attr->value.size);
                if (result) {
                    memcpy(result, attr->value.value.byteVectorValue, attr->value.size);
                    *out_size = attr->value.size;
                }
                taglib_complex_property_free(props);
                return result;
            }
        }
    }
    taglib_complex_property_free(props);
    return NULL;
}
