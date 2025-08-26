#!/usr/bin/env bash
#
# cleanup-demo-artifacts.sh
# Removes scaffold/demo files from an Alfresco SDK-style repo.
# Works on macOS (BSD find) and Linux (GNU find).
#
# Usage:
#   ./cleanup-demo-artifacts.sh            # interactive confirm
#   ./cleanup-demo-artifacts.sh -n         # dry-run (show what would be removed)
#   ./cleanup-demo-artifacts.sh -y         # no prompt (non-interactive)
#   ./cleanup-demo-artifacts.sh --with-docker  # also remove docker modules, run scripts, README
#
set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
WITH_DOCKER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) DRY_RUN=1 ;;
    -y) ASSUME_YES=1 ;;
    --with-docker) WITH_DOCKER=1 ;;
    *) echo "Usage: $0 [-n] [-y] [--with-docker]"; exit 2 ;;
  esac
  shift
done

# Guardrail: ensure we're at the repo root (pom.xml present).
if [[ ! -f "pom.xml" ]]; then
  echo "✖ This doesn't look like the project root (missing pom.xml)."
  exit 1
fi

say() { printf "%s\n" "$*"; }
sep() { printf "%s\n" "------------------------------------------------------------"; }

# ---------------------------------------------------------------------
# Core items (independent of module names)
# ---------------------------------------------------------------------
read -r -d '' ITEMS <<'EOF' || true
CustomContentModelIT.java|*/src/*/java/*/platformsample/*
DemoComponentIT.java|*/src/*/java/*/platformsample/*
HelloWorldWebScriptIT.java|*/src/*/java/*/platformsample/*

Demo.java|*/src/main/java/*/platformsample/*
DemoComponent.java|*/src/main/java/*/platformsample/*
HelloWorldWebScript.java|*/src/main/java/*/platformsample/*

helloworld.get.desc.xml|*/src/main/resources/alfresco/extension/templates/webscripts/alfresco/tutorials/*
helloworld.get.html.ftl|*/src/main/resources/alfresco/extension/templates/webscripts/alfresco/tutorials/*
helloworld.get.js|*/src/main/resources/alfresco/extension/templates/webscripts/alfresco/tutorials/*

content-model.properties|*/src/main/resources/alfresco/module/*/messages/*
workflow-messages.properties|*/src/main/resources/alfresco/module/*/messages/*
content-model.xml|*/src/main/resources/alfresco/module/*/model/*
workflow-model.xml|*/src/main/resources/alfresco/module/*/model/*
bootstrap-context.xml|*/src/main/resources/alfresco/module/*/context/*
service-context.xml|*/src/main/resources/alfresco/module/*/context/*
webscript-context.xml|*/src/main/resources/alfresco/module/*/context/*
sample-process.bpmn20.xml|*/src/main/resources/alfresco/module/*/workflow/*

test.html|*/src/main/resources/META-INF/resources/*

HelloWorldWebScriptControllerTest.java|*/src/test/java/*/platformsample/*

*-share.properties|*/src/main/resources/alfresco/web-extension/messages/*
*-example-widgets.xml|*/src/main/resources/alfresco/web-extension/site-data/extensions/*
*-slingshot-application-context.xml|*/src/main/resources/alfresco/web-extension/*
- share-config-custom.xml|*/src/main/resources/*

simple-page.get.desc.xml|*/src/main/resources/alfresco/web-extension/site-webscripts/com/example/pages/*
simple-page.get.html.ftl|*/src/main/resources/alfresco/web-extension/site-webscripts/com/example/pages/*
simple-page.get.js|*/src/main/resources/alfresco/web-extension/site-webscripts/com/example/pages/*
README.md|*/src/main/resources/alfresco/web-extension/site-webscripts/org/alfresco/*

TemplateWidget.css|*/src/main/resources/META-INF/resources/*/js/tutorials/widgets/css/*
TemplateWidget.properties|*/src/main/resources/META-INF/resources/*/js/tutorials/widgets/i18n/*
TemplateWidget.html|*/src/main/resources/META-INF/resources/*/js/tutorials/widgets/templates/*
TemplateWidget.js|*/src/main/resources/META-INF/resources/*/js/tutorials/widgets/*
EOF

TO_REMOVE=()

process_items() {
  local items="$1"
  IFS=$'\n'
  for raw in $items; do
    # strip inline comments and whitespace
    local line="${raw%%#*}"
    line="$(printf '%s' "$line" | awk '{$1=$1;print}')"
    [[ -z "$line" ]] && continue

    local name="${line%%|*}"
    local pathfrag="${line#*|}"

    while IFS= read -r -d '' f; do
      TO_REMOVE+=("$f")
    done < <(find . -type f -name "$name" -path "$pathfrag" -print0 2>/dev/null || true)
  done
}

process_items "$ITEMS"

strip_docker_modules_from_pom() {
  local pom="pom.xml"
  [[ -f "$pom" ]] || { echo "pom.xml not found"; return 1; }

  awk '
    /<modules>/   { inblock=1 }
    /<\/modules>/ { inblock=0 }
    inblock && $0 ~ /<module>[[:space:]]*docker[[:space:]]*<\/module>/        { next }
    inblock && $0 ~ /<module>[[:space:]]*[^<]*-platform-docker[[:space:]]*<\/module>/ { next }
    inblock && $0 ~ /<module>[[:space:]]*[^<]*-share-docker[[:space:]]*<\/module>/    { next }
    inblock && $0 ~ /<module>[[:space:]]*[^<]*-docker[[:space:]]*<\/module>/          { next }
    { print }
  ' "$pom" > "${pom}.tmp" && mv "${pom}.tmp" "$pom"
}

if (( WITH_DOCKER )); then
  for f in "./run.sh" "./run.bat" "./README.md"; do
    [[ -f "$f" ]] && TO_REMOVE+=("$f")
  done
  while IFS= read -r -d '' d; do
    TO_REMOVE+=("$d")
  done < <(find . -maxdepth 1 -type d \( -name "docker" -o -name "*-platform-docker" -o -name "*-share-docker" \) -print0 2>/dev/null || true)
  strip_docker_modules_from_pom
fi

# De-duplicate & sort
if [[ ${#TO_REMOVE[@]} -gt 0 ]]; then
  mapfile -t TO_REMOVE < <(printf "%s\n" "${TO_REMOVE[@]}" | awk '!seen[$0]++' | sort)
fi

sep
if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
  say "No matching demo/tutorial files found. Nothing to do."
  exit 0
fi

say "The following will be REMOVED (${#TO_REMOVE[@]}):"
printf "  %s\n" "${TO_REMOVE[@]}"
sep

if (( DRY_RUN )); then
  say "Dry-run mode: no changes made."
  exit 0
fi

if (( ! ASSUME_YES )); then
  read -r -p "Proceed with deletion? [y/N] " ans
  case "${ans:-N}" in
    y|Y) ;;
    *) say "Aborted."; exit 1 ;;
  esac
fi

# Remove files and directories
for f in "${TO_REMOVE[@]}"; do
  rm -rf -- "$f" 2>/dev/null || rm -rf "$f"
done

strip_module_context_imports() {
  while IFS= read -r -d '' mc; do

    awk '
      /classpath:alfresco\/module\/.*\/context\/bootstrap-context\.xml/ { next }
      /classpath:alfresco\/module\/.*\/context\/service-context\.xml/   { next }
      /classpath:alfresco\/module\/.*\/context\/webscript-context\.xml/ { next }
      { print }
    ' "$mc" > "${mc}.tmp" && mv "${mc}.tmp" "$mc"

    printf "  cleaned: %s\n" "$mc"
  done < <(find . -type f -path "*/src/main/resources/alfresco/module/*/module-context.xml" -print0 2>/dev/null || true)
}

ensure_minimal_share_config() {
  # Minimal skeleton
  local skeleton='<?xml version="1.0" encoding="UTF-8"?>
<alfresco-config/>'

  while IFS= read -r -d '' resdir; do
    if [[ -d "$resdir/alfresco/web-extension" ]]; then
      local target="$resdir/share-config-custom.xml"
      if [[ -f "$target" ]] && grep -q "<alfresco-config" "$target" 2>/dev/null; then
        printf "  keep   : %s (already contains <alfresco-config>)\n" "$target"
      else
        printf "%s\n" "$skeleton" > "$target"
        printf "  wrote  : %s\n" "$target"
      fi
    fi
  done < <(find . -type d -path "*/src/main/resources" -print0 2>/dev/null || true)
}

say "Updating XML configs..."
strip_module_context_imports
ensure_minimal_share_config


# Clean up empty dirs in all modules
say "Cleaning up empty directories..."
while IFS= read -r -d '' modsrc; do
  find "$(dirname "$modsrc")/src" -type d -empty -delete 2>/dev/null || true
done < <(find . -mindepth 2 -maxdepth 2 -type d -name src -print0 2>/dev/null || true)

sep
say "Done. Removed ${#TO_REMOVE[@]} items and pruned empty directories."
