#!/bin/sh
# Refuses pushed commits without a message.
zero=0000000000000000000000000000000000000000
while read -r old new _; do
  [ "$new" = "$zero" ] && continue
  if [ "$old" = "$zero" ]; then
    set -- "$new" --not --branches
  else
    set -- "$old..$new"
  fi
  # An empty subject ends in a space.
  if git log --format='%H %s' "$@" | grep -q ' $'; then
    echo "Every commit needs a message; amend and push again." >&2
    exit 1
  fi
done
