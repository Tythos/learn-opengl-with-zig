// C wrapper for stb_image to avoid Zig translation issues
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_SIMD
#include "stb_image.h"

// The stb functions are now available to link against
// No additional wrapper functions needed - we just need this translation unit
// to provide the implementation
