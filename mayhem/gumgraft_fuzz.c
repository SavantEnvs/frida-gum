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
 * per-process scratch file under /tmp and grafts it. The flags mirror the
 * historical deployed command `gum-graft -s -m` (INGEST_FUNCTION_STARTS |
 * INGEST_IMPORTS). Coverage now comes from the sanitizer-coverage-instrumented
 * libfrida-gum linked into this harness (see mayhem/build.sh).
 */

#include <gum/gum.h>
#include <gum/gumdarwingrafter.h>

#include <glib.h>
#include <stdint.h>
#include <unistd.h>

static gchar * input_path = NULL;

int
LLVMFuzzerInitialize (int * argc,
                      char *** argv)
{
  gum_init ();
  input_path = g_strdup_printf ("/tmp/gum-graft-fuzz-%d.macho", (int) getpid ());
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
