#define _GNU_SOURCE

#include <dlfcn.h>
#include <png.h>
#include <stdlib.h>

/*
 * Abaqus vendors binaries linked against libpng 1.2's PNG12_0 symbol
 * versions.  libpng 1.6 is API-compatible for the symbols used here, but it
 * exports them as PNG16_0 and refuses the old version string.  Forward each
 * call to libpng16 while keeping the old symbol versions and soname.
 */

#define FORWARD(ret, name, params, args)                                      \
  ret name params                                                             \
  {                                                                           \
    static ret (*fn) params;                                                   \
    if (fn == NULL)                                                            \
      fn = (ret (*) params) dlvsym (RTLD_NEXT, #name, "PNG16_0");            \
    if (fn == NULL)                                                            \
      abort ();                                                               \
    return fn args;                                                            \
  }

static png_structp
create_struct (const char *fn_name, png_voidp error_ptr,
               png_error_ptr error_fn, png_error_ptr warn_fn)
{
  png_structp (*fn) (const char *, png_voidp, png_error_ptr, png_error_ptr);
  fn = (png_structp (*) (const char *, png_voidp, png_error_ptr,
                         png_error_ptr)) dlvsym (RTLD_NEXT, fn_name, "PNG16_0");
  if (fn == NULL)
    abort ();

  return fn (PNG_LIBPNG_VER_STRING, error_ptr, error_fn, warn_fn);
}

png_structp
png_create_read_struct (png_const_charp user_png_ver, png_voidp error_ptr,
                        png_error_ptr error_fn, png_error_ptr warn_fn)
{
  (void) user_png_ver;
  return create_struct ("png_create_read_struct", error_ptr, error_fn, warn_fn);
}

png_structp
png_create_write_struct (png_const_charp user_png_ver, png_voidp error_ptr,
                         png_error_ptr error_fn, png_error_ptr warn_fn)
{
  (void) user_png_ver;
  return create_struct ("png_create_write_struct", error_ptr, error_fn, warn_fn);
}

FORWARD (png_infop, png_create_info_struct, (png_const_structrp png_ptr),
         (png_ptr))
FORWARD (void, png_destroy_read_struct,
         (png_structpp png_ptr_ptr, png_infopp info_ptr_ptr,
          png_infopp end_info_ptr_ptr),
         (png_ptr_ptr, info_ptr_ptr, end_info_ptr_ptr))
FORWARD (void, png_destroy_write_struct,
         (png_structpp png_ptr_ptr, png_infopp info_ptr_ptr),
         (png_ptr_ptr, info_ptr_ptr))
void
png_error (png_const_structrp png_ptr, png_const_charp error_message)
{
  static void (*fn) (png_const_structrp, png_const_charp);
  if (fn == NULL)
    fn = (void (*) (png_const_structrp, png_const_charp)) dlvsym (
        RTLD_NEXT, "png_error", "PNG16_0");
  if (fn == NULL)
    abort ();
  fn (png_ptr, error_message);
  abort ();
}

FORWARD (png_uint_32, png_get_IHDR,
         (png_const_structrp png_ptr, png_const_inforp info_ptr,
          png_uint_32 *width, png_uint_32 *height, int *bit_depth,
          int *color_type, int *interlace_method, int *compression_method,
          int *filter_method),
         (png_ptr, info_ptr, width, height, bit_depth, color_type,
          interlace_method, compression_method, filter_method))
FORWARD (png_uint_32, png_get_PLTE,
         (png_const_structrp png_ptr, png_inforp info_ptr,
          png_colorp *palette, int *num_palette),
         (png_ptr, info_ptr, palette, num_palette))
FORWARD (png_byte, png_get_bit_depth,
         (png_const_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (png_byte, png_get_channels,
         (png_const_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (png_byte, png_get_color_type,
         (png_const_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (png_uint_32, png_get_gAMA,
         (png_const_structrp png_ptr, png_const_inforp info_ptr,
          double *file_gamma),
         (png_ptr, info_ptr, file_gamma))
FORWARD (png_uint_32, png_get_image_height,
         (png_const_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (png_uint_32, png_get_image_width,
         (png_const_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (png_voidp, png_get_io_ptr, (png_const_structrp png_ptr), (png_ptr))
FORWARD (size_t, png_get_rowbytes,
         (png_const_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (png_uint_32, png_get_sBIT,
         (png_const_structrp png_ptr, png_inforp info_ptr,
          png_color_8p *sig_bit),
         (png_ptr, info_ptr, sig_bit))
FORWARD (png_uint_32, png_get_tRNS,
         (png_const_structrp png_ptr, png_inforp info_ptr,
          png_bytep *trans_alpha, int *num_trans,
          png_color_16p *trans_color),
         (png_ptr, info_ptr, trans_alpha, num_trans, trans_color))
FORWARD (int, png_get_text,
         (png_const_structrp png_ptr, png_inforp info_ptr,
          png_textp *text_ptr, int *num_text),
         (png_ptr, info_ptr, text_ptr, num_text))
FORWARD (png_uint_32, png_get_valid,
         (png_const_structrp png_ptr, png_const_inforp info_ptr,
          png_uint_32 flag),
         (png_ptr, info_ptr, flag))
FORWARD (png_uint_32, png_get_x_pixels_per_meter,
         (png_const_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (png_uint_32, png_get_y_pixels_per_meter,
         (png_const_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (void, png_init_io, (png_structrp png_ptr, FILE *fp), (png_ptr, fp))
FORWARD (void, png_read_end, (png_structrp png_ptr, png_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (void, png_read_image, (png_structrp png_ptr, png_bytepp image),
         (png_ptr, image))
FORWARD (void, png_read_info, (png_structrp png_ptr, png_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (void, png_read_update_info,
         (png_structrp png_ptr, png_inforp info_ptr), (png_ptr, info_ptr))

FORWARD (void, png_set_IHDR,
         (png_const_structrp png_ptr, png_inforp info_ptr,
          png_uint_32 width, png_uint_32 height, int bit_depth,
          int color_type, int interlace_method, int compression_method,
          int filter_method),
         (png_ptr, info_ptr, width, height, bit_depth, color_type,
          interlace_method, compression_method, filter_method))
FORWARD (void, png_set_PLTE,
         (png_structrp png_ptr, png_inforp info_ptr,
          png_const_colorp palette, int num_palette),
         (png_ptr, info_ptr, palette, num_palette))
FORWARD (void, png_set_bgr, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_compression_level,
         (png_structrp png_ptr, int level), (png_ptr, level))
FORWARD (void, png_set_error_fn,
         (png_structrp png_ptr, png_voidp error_ptr, png_error_ptr error_fn,
          png_error_ptr warning_fn),
         (png_ptr, error_ptr, error_fn, warning_fn))
FORWARD (void, png_set_expand, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_filler,
         (png_structrp png_ptr, png_uint_32 filler, int flags),
         (png_ptr, filler, flags))
FORWARD (void, png_set_filter,
         (png_structrp png_ptr, int method, int filters),
         (png_ptr, method, filters))
FORWARD (void, png_set_gAMA,
         (png_const_structrp png_ptr, png_inforp info_ptr, double file_gamma),
         (png_ptr, info_ptr, file_gamma))
FORWARD (void, png_set_gamma,
         (png_structrp png_ptr, double screen_gamma,
          double override_file_gamma),
         (png_ptr, screen_gamma, override_file_gamma))
FORWARD (void, png_set_gray_to_rgb, (png_structrp png_ptr), (png_ptr))
FORWARD (int, png_set_interlace_handling, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_invert_mono, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_oFFs,
         (png_const_structrp png_ptr, png_inforp info_ptr, png_int_32 offset_x,
          png_int_32 offset_y, int unit_type),
         (png_ptr, info_ptr, offset_x, offset_y, unit_type))
FORWARD (void, png_set_pHYs,
         (png_const_structrp png_ptr, png_inforp info_ptr, png_uint_32 res_x,
          png_uint_32 res_y, int unit_type),
         (png_ptr, info_ptr, res_x, res_y, unit_type))
FORWARD (void, png_set_packing, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_packswap, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_palette_to_rgb, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_read_fn,
         (png_structrp png_ptr, png_voidp io_ptr, png_rw_ptr read_data_fn),
         (png_ptr, io_ptr, read_data_fn))
FORWARD (void, png_set_sBIT,
         (png_const_structrp png_ptr, png_inforp info_ptr,
          png_const_color_8p sig_bit),
         (png_ptr, info_ptr, sig_bit))
FORWARD (void, png_set_shift,
         (png_structrp png_ptr, png_const_color_8p true_bits),
         (png_ptr, true_bits))
FORWARD (void, png_set_sig_bytes, (png_structrp png_ptr, int num_bytes),
         (png_ptr, num_bytes))
FORWARD (void, png_set_strip_16, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_swap, (png_structrp png_ptr), (png_ptr))
FORWARD (void, png_set_tRNS,
         (png_structrp png_ptr, png_inforp info_ptr,
          png_const_bytep trans_alpha, int num_trans,
          png_const_color_16p trans_color),
         (png_ptr, info_ptr, trans_alpha, num_trans, trans_color))
FORWARD (void, png_set_text,
         (png_const_structrp png_ptr, png_inforp info_ptr,
          png_const_textp text_ptr, int num_text),
         (png_ptr, info_ptr, text_ptr, num_text))
FORWARD (void, png_set_write_fn,
         (png_structrp png_ptr, png_voidp io_ptr, png_rw_ptr write_data_fn,
          png_flush_ptr output_flush_fn),
         (png_ptr, io_ptr, write_data_fn, output_flush_fn))
FORWARD (int, png_sig_cmp,
         (png_const_bytep sig, size_t start, size_t num_to_check),
         (sig, start, num_to_check))
FORWARD (void, png_write_chunk,
         (png_structrp png_ptr, png_const_bytep chunk_name,
          png_const_bytep data, png_size_t length),
         (png_ptr, chunk_name, data, length))
FORWARD (void, png_write_end, (png_structrp png_ptr, png_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (void, png_write_image, (png_structrp png_ptr, png_bytepp image),
         (png_ptr, image))
FORWARD (void, png_write_info,
         (png_structrp png_ptr, png_const_inforp info_ptr),
         (png_ptr, info_ptr))
FORWARD (void, png_write_rows,
         (png_structrp png_ptr, png_bytepp row, png_uint_32 num_rows),
         (png_ptr, row, num_rows))
