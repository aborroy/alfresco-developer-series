<# 
cleanup-demo-artifacts.ps1
Removes scaffold/demo files from an Alfresco SDK-style repo on Windows.

Usage:
  # interactive confirm
  .\cleanup-demo-artifacts.ps1

  # dry-run (show what would be removed)
  .\cleanup-demo-artifacts.ps1 -DryRun

  # no prompt (non-interactive)
  .\cleanup-demo-artifacts.ps1 -Yes

  # also remove docker modules, run scripts, README and strip docker modules in root pom.xml
  .\cleanup-demo-artifacts.ps1 -WithDocker
#>

param(
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$WithDocker
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg) { Write-Host $msg }
function Sep() { Write-Host ('-'*60) }

# Guardrail
if (-not (Test-Path -LiteralPath 'pom.xml')) {
  Write-Error "This doesn't look like the project root (missing pom.xml)."
  exit 1
}

# ------------------------------
# Patterns: "name|path-fragment"
# NOTE: Windows backslashes are used for path-matching (-like), we convert '/' -> '\'
# ------------------------------
$ItemsSpec = @'
CustomContentModelIT.java|*\src\*\java\*\platformsample\*
DemoComponentIT.java|*\src\*\java\*\platformsample\*
HelloWorldWebScriptIT.java|*\src\*\java\*\platformsample\*

Demo.java|*\src\main\java\*\platformsample\*
DemoComponent.java|*\src\main\java\*\platformsample\*
HelloWorldWebScript.java|*\src\main\java\*\platformsample\*

helloworld.get.desc.xml|*\src\main\resources\alfresco\extension\templates\webscripts\alfresco\tutorials\*
helloworld.get.html.ftl|*\src\main\resources\alfresco\extension\templates\webscripts\alfresco\tutorials\*
helloworld.get.js|*\src\main\resources\alfresco\extension\templates\webscripts\alfresco\tutorials\*

content-model.properties|*\src\main\resources\alfresco\module\*\messages\*
workflow-messages.properties|*\src\main\resources\alfresco\module\*\messages\*
content-model.xml|*\src\main\resources\alfresco\module\*\model\*
workflow-model.xml|*\src\main\resources\alfresco\module\*\model\*
bootstrap-context.xml|*\src\main\resources\alfresco\module\*\context\*
service-context.xml|*\src\main\resources\alfresco\module\*\context\*
webscript-context.xml|*\src\main\resources\alfresco\module\*\context\*
sample-process.bpmn20.xml|*\src\main\resources\alfresco\module\*\workflow\*

test.html|*\src\main\resources\META-INF\resources\*

HelloWorldWebScriptControllerTest.java|*\src\test\java\*\platformsample\*

*-share.properties|*\src\main\resources\alfresco\web-extension\messages\*
*-example-widgets.xml|*\src\main\resources\alfresco\web-extension\site-data\extensions\*
*-slingshot-application-context.xml|*\src\main\resources\alfresco\web-extension\*

simple-page.get.desc.xml|*\src\main\resources\alfresco\web-extension\site-webscripts\com\example\pages\*
simple-page.get.html.ftl|*\src\main\resources\alfresco\web-extension\site-webscripts\com\example\pages\*
simple-page.get.js|*\src\main\resources\alfresco\web-extension\site-webscripts\com\example\pages\*
README.md|*\src\main\resources\alfresco\web-extension\site-webscripts\org\alfresco\*

TemplateWidget.css|*\src\main\resources\META-INF\resources\*\js\tutorials\widgets\css\*
TemplateWidget.properties|*\src\main\resources\META-INF\resources\*\js\tutorials\widgets\i18n\*
TemplateWidget.html|*\src\main\resources\META-INF\resources\*\js\tutorials\widgets\templates\*
TemplateWidget.js|*\src\main\resources\META-INF\resources\*\js\tutorials\widgets\*
'@ -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') }

$ToRemove = New-Object System.Collections.Generic.List[string]

function Resolve-Items([string[]]$specLines) {
  foreach ($line in $specLines) {
    $name, $frag = $line -split '\|', 2
    if (-not $frag) { continue }
    # normalize wildcard fragment (already backslashes in $ItemsSpec)
    $pattern = ('*' + ($frag.Trim('*')) + '*').Replace('**','*')
    # search by leaf name, then filter by path pattern
    Get-ChildItem -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -like $pattern } |
      ForEach-Object { $ToRemove.Add($_.FullName) }
  }
}

Resolve-Items -specLines $ItemsSpec

if ($WithDocker) {
  # extra top-level files
  foreach ($f in @('.\run.sh', '.\run.bat', '.\README.md')) {
    if (Test-Path -LiteralPath $f) { $ToRemove.Add((Resolve-Path $f).Path) }
  }
  # docker folders: .\docker, .\*-platform-docker, .\*-share-docker
  Get-ChildItem -Path . -Directory -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -eq 'docker' -or
      $_.Name -like '*-platform-docker' -or
      $_.Name -like '*-share-docker'
    } | ForEach-Object { $ToRemove.Add($_.FullName) }
}

# De-dup and sort
$ToRemove = $ToRemove | Sort-Object -Unique

Sep
if (-not $ToRemove -or $ToRemove.Count -eq 0) {
  Say "No matching demo/tutorial files found. Nothing to do."
} else {
  Say ("The following will be REMOVED ({0}):" -f $ToRemove.Count)
  $ToRemove | ForEach-Object { "  $_" } | Write-Host
}
Sep

if ($DryRun) {
  Say "Dry-run mode: no changes made."
  exit 0
}

if (-not $Yes) {
  $ans = Read-Host "Proceed with deletion? [y/N]"
  if ($ans -ne 'y' -and $ans -ne 'Y') { Say 'Aborted.'; exit 1 }
}

# Remove files/dirs
foreach ($p in $ToRemove) {
  if (Test-Path -LiteralPath $p) {
    Remove-Item -LiteralPath $p -Force -Recurse -ErrorAction SilentlyContinue
  }
}

# --- Root pom.xml: strip docker modules when requested (no external tools) ---
function Strip-DockerModulesFromPom {
  $pom = 'pom.xml'
  if (-not (Test-Path -LiteralPath $pom)) { return }
  $lines = Get-Content -LiteralPath $pom -Raw -Encoding UTF8 -ErrorAction SilentlyContinue -TotalCount 999999 -ReadCount 0
  $out = New-Object System.Text.StringBuilder
  $inModules = $false

  foreach ($line in $lines -split "`r?`n") {
    if ($line -match '<modules>') { $inModules = $true }
    if ($inModules) {
      # skip docker entries
      if ($line -match '<module>\s*docker\s*</module>' `
        -or $line -match '<module>\s*[^<]*-platform-docker\s*</module>' `
        -or $line -match '<module>\s*[^<]*-share-docker\s*</module>' `
        -or $line -match '<module>\s*[^<]*-docker\s*</module>') {
        continue
      }
    }
    if ($line -match '</modules>') { $inModules = $false }
    [void]$out.AppendLine($line)
  }
  Set-Content -LiteralPath $pom -Value $out.ToString() -NoNewline -Encoding UTF8
}

if ($WithDocker) { Strip-DockerModulesFromPom }

# --- XML edits (ALWAYS) ---

function Strip-ModuleContextImports {
  # Remove context imports from each module-context.xml
  $pattern = 'classpath:alfresco/module/.*/context/(bootstrap|service|webscript)-context\.xml'
  Get-ChildItem -Recurse -File -Filter 'module-context.xml' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like '*\src\main\resources\alfresco\module\*\module-context.xml' } |
    ForEach-Object {
      $path = $_.FullName
      $content = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
      $new = $content | Where-Object { $_ -notmatch $pattern }
      if ($null -ne $new) {
        Set-Content -LiteralPath $path -Value $new -Encoding UTF8
        Write-Host ("  cleaned: {0}" -f $path)
      }
    }
}

function Ensure-MinimalShareConfig {
  # Only for Share modules: those that contain src\main\resources\alfresco\web-extension
  $skeleton = @'
<?xml version="1.0" encoding="UTF-8"?>
<alfresco-config/>
'@
  Get-ChildItem -Recurse -Directory -ErrorAction SilentlyContinue -Filter resources |
    Where-Object { $_.FullName -like '*\src\main\resources' } |
    ForEach-Object {
      $resDir = $_.FullName
      $webExt = Join-Path $resDir 'alfresco\web-extension'
      if (Test-Path -LiteralPath $webExt) {
        $target = Join-Path $resDir 'share-config-custom.xml'
        if ((Test-Path -LiteralPath $target) -and (Select-String -Path $target -Pattern '<alfresco-config' -SimpleMatch -Quiet)) {
          Write-Host ("  keep   : {0} (already contains <alfresco-config>)" -f $target)
        } else {
          Set-Content -LiteralPath $target -Value $skeleton -Encoding UTF8
          Write-Host ("  wrote  : {0}" -f $target)
        }
      }
    }
}

Say "Updating XML configs..."
Strip-ModuleContextImports
Ensure-MinimalShareConfig

# --- Prune empty directories under any module's src/ ---
Say "Cleaning up empty directories..."
Get-ChildItem -Recurse -Directory -ErrorAction SilentlyContinue -Filter src |
  Where-Object { $_.Name -eq 'src' } |
  ForEach-Object {
    # remove empties bottom-up
    Get-ChildItem -Path $_.FullName -Directory -Recurse -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      ForEach-Object {
        if (-not (Get-ChildItem -Force -Recurse -LiteralPath $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 1)) {
          Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
        }
      }
    # if src itself ended up empty, attempt to remove
    if (-not (Get-ChildItem -Force -LiteralPath $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 1)) {
      Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
    }
  }

Sep
Say "Done."
