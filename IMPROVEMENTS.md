# Improvement progress

Target: 100 independently reviewable improvements. Completed in this batch: 19. The target is not complete. Test cases and formatting edits are not counted separately.

1. JSON parsing rejects trailing non-whitespace data.
2. JSON numbers require integer digits and reject leading zeroes.
3. JSON fractional numbers require digits after the decimal point.
4. JSON exponents require digits after their optional sign.
5. JSON exponents affect the parsed numeric value.
6. JSON exponent processing is bounded for very large exponents.
7. Unknown string escapes and raw control characters are rejected.
8. JSON Unicode escapes decode BMP characters and surrogate pairs.
9. Malformed hexadecimal and unpaired surrogate escapes are rejected.
10. JSON strings support slash, backspace and form-feed escapes.
11. Log serialization escapes all ASCII control characters.
12. Stream serialization escapes all ASCII control characters.
13. Time-series serialization escapes controls and preserves character text.
14. Three existing tests assert values instead of deprecated display formatting.
15. The module defaults to JavaScript so check/test/info work without target flags.
16. Generated builds, staged sites and generated interfaces are ignored by Git.
17. Pages deployment fails on unsuccessful build/check/test.
18. Pages staging requires both release entry points and copies exact assets.
19. Push/PR CI validates check, tests, release builds and site staging.

## Validation

moon info, moon fmt, moon check, moon test (67/67), release JS build and exact site staging passed. Existing deprecation/unused-value warnings remain.
