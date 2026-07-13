/*
 * In-process libFuzzer harness for frida-gum's Darwin (Mach-O) grafter.
 *
 * The upstream gum-graft CLI (tools/gumgraft.c) is a raw file-input tool: it
 * parses a Mach-O with gum_darwin_grafter_new_from_file() and rewrites it in
 * place with gum_darwin_grafter_graft() (which parses via
 * gum_darwin_module_new_from_file). Run as a raw CLI under Mayhem it produced
 * ZERO coverage edges (no in-process instrumentation feedback), so per the
 * porting harness policy we drive the SAME code path in-process instead.
 *
 * The grafter API is file-based, so each iteration writes the fuzz bytes to a
 * per-process scratch file and grafts it. The file is created once with
 * g_file_open_tmp(), i.e. mkstemp() in g_get_tmp_dir() ($TMPDIR, else /tmp), so
 * its name is unique and unpredictable (PORTING.md: no hardcoded scratch paths),
 * and it is removed at exit. The flags mirror the
 * historical deployed command `gum-graft -s -m` (INGEST_FUNCTION_STARTS |
 * INGEST_IMPORTS). Coverage now comes from the sanitizer-coverage-instrumented
 * libfrida-gum linked into this harness (see mayhem/build.sh).
 */

#include <gum/gum.h>
#include <gum/gumdarwingrafter.h>

#include <glib.h>
#include <glib/gstdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

static gchar * input_path = NULL;

static void
remove_input_file (void)
{
  if (input_path != NULL)
    g_unlink (input_path);
}

int
LLVMFuzzerInitialize (int * argc,
                      char *** argv)
{
  gint fd;

  gum_init ();

  fd = g_file_open_tmp ("gum-graft-fuzz-XXXXXX.macho", &input_path, NULL);
  if (fd == -1)
    g_error ("gum-graft fuzz harness: cannot create a scratch file in %s",
        g_get_tmp_dir ());
  close (fd);
  atexit (remove_input_file);

  return 0;
}

int
LLVMFuzzerTestOneInput (const uint8_t * data,
                        size_t size)
{
  GumDarwinGrafter * grafter;
  GError * error = NULL;

  if (!g_file_set_contents (input_path, (const gchar *) data, (gssize) size,
      NULL))
  {
    return 0;
  }

  grafter = gum_darwin_grafter_new_from_file (input_path,
      GUM_DARWIN_GRAFTER_FLAGS_INGEST_FUNCTION_STARTS |
      GUM_DARWIN_GRAFTER_FLAGS_INGEST_IMPORTS);

  gum_darwin_grafter_graft (grafter, &error);

  g_clear_error (&error);
  g_object_unref (grafter);

  return 0;
}
