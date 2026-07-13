/*
 * Build-time LeakSanitizer opt-out, linked into every gum-graft binary.
 *
 * -fsanitize=address always bundles LSan in and there is no flag to keep ASan's
 * memory-corruption checks while dropping leak detection, so the sanctioned way to turn
 * leak reporting off is this weak-symbol hook resolved at link time. Leaks are not the bug
 * class this fleet fuzzes for (frida-gum's GObject/GLib type system intentionally leaks
 * one-time type registrations), and ASan + UBSan stay fully enabled and halting.
 *
 * Build-time only, per fleet policy: no runtime toggling, and Mayhem alone owns the
 * sanitizer runtime option set.
 *
 * Declared on one line (not frida's usual GNU layout) so the conformance gate's
 * single-line `int __lsan_is_turned_off (` grep actually sees the hook.
 */
int __lsan_is_turned_off (void)
{
  return 1;
}
