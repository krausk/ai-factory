#!/bin/bash
# The human checkpoint: promotes a bean from "refinement complete, awaiting
# approval" to "approved, ready for development". This is the one pipeline
# transition that's deliberately never done automatically — see
# docs/PIPELINE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ne 1 ]; then
    echo "Usage: $0 <bean-id>" >&2
    exit 1
fi

id="$1"

status=$(beans show "$id" --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || echo "")
tags=$(beans show "$id" --json | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin).get("tags",[])))' 2>/dev/null || echo "")

case ",$tags," in
    *,stage:refinement,*) ;;
    *)
        echo "Warning: $id doesn't have the stage:refinement tag (tags: $tags) — approving anyway, but double-check this is the bean you meant." >&2
        ;;
esac

if [ "$status" != "completed" ]; then
    echo "Warning: $id's status is '$status', not 'completed' — the refinement stage may not actually be done yet." >&2
fi

beans update "$id" --tag stage:development --remove-tag stage:refinement -s todo
echo "Approved: $id is now stage:development/todo — the watcher will pick it up next pass."
