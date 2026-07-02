#!/usr/bin/env bash
# slugify.sh — a tiny, pure-shell fixture function (no repo dependency).
#
# slugify(): given a string, produce a URL-friendly slug:
#   - lowercase all characters
#   - replace every run of non-alphanumeric characters with a single '-'
#   - trim leading/trailing '-'
# Empty input (or input with no alphanumerics) yields the empty string.
#
# Source this file and call `slugify "<text>"`; the slug is printed on stdout.

slugify() {
  local s="$1"
  # lowercase
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  # non-alphanumeric runs -> single '-'
  s="$(printf '%s' "$s" | tr -cs '[:alnum:]' '-')"
  # trim leading/trailing '-'
  s="${s#-}"
  s="${s%-}"
  printf '%s' "$s"
}
