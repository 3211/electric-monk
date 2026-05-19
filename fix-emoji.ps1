# Fix corrupted emoji remnants in all Vue files
# Corrupted patterns: variation selector bytes stripped, leaving "E" in broken tags

$files = Get-ChildItem -Path src -Filter *.vue -Recurse
$fixCount = 0

foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    $original = $text

    # Pattern: emoji + "E" + "/span>"  →  proper closing tag
    # ⚔️ corrupted to ⚔E/span>
    $text = $text -replace ([regex]::Escape("⚔E/span>")), "⚔️</span>"

    # ⚔E/div> → 💰</div>
    $text = $text -replace ([regex]::Escape("⚔E/div>")), "💰</div>"

    # ◁ELive → ● Live
    $text = $text -replace ([regex]::Escape("◁ELive")), "● Live"

    # ⚔E↔E-24h → 💰 -24h
    $text = $text -replace "⚔E.*?24h", "💰 -24h"

    # ⚔︁ESynod → ⚔️ Synod  (ReliquaryView)
    $text = $text -replace "⚔︁ESynod", "⚔️ Synod"

    # ⚔︁EAttempt → ⚔️ Attempt
    $text = $text -replace "⚔︁EAttempt", "⚔️ Attempt"

    # ✁E/span> → ✝️</span>  (VaticanView already fixed, just in case)
    $text = $text -replace ([regex]::Escape("✁E/span>")), "✝️</span>"

    # ✁ECatacombs → ✝️ Catacombs
    $text = $text -replace "✁ECatacombs", "✝️ Catacombs"

    # ✁EIn → ✝️ In  (ReliquaryView)
    $text = $text -replace "✁EIn", "✝️ In"

    # ✁EActive → ✝️ Active
    $text = $text -replace "✁EActive", "✝️ Active"

    # 🕯EE → 🕯️
    $text = $text -replace "🕯EE", "🕯️"

    # ⚁E/span> → 🎲</span>  (any remaining)
    $text = $text -replace ([regex]::Escape("⚁E/span>")), "🎲</span>"

    # 🛡EEProtected → 🛡️ Protected
    $text = $text -replace "🛡EEProtected", "🛡️ Protected"

    # 🏗EE/span> → 🏗️</span>
    $text = $text -replace ([regex]::Escape("🏗EE/span>")), "🏗️</span>"

    # 🏛EESects → 🏛️ Sects
    $text = $text -replace "🏛EESects", "🏛️ Sects"

    # 🏛EEOverview → 🏛️ Overview
    $text = $text -replace "🏛EEOverview", "🏛️ Overview"

    # 🏛EE/div> → 🏛️</div>
    $text = $text -replace ([regex]::Escape("🏛EE/div>")), "🏛️</div>"

    # 🏛EE → 🏛️  (in FactionCoreSealIcon fallback)
    $text = $text -replace "🏛EE", "🏛️"

    # ⚠EE/div> → ⚠️</div>
    $text = $text -replace ([regex]::Escape("⚠EE/div>")), "⚠️</div>"

    # 🕊️🙏 — if previously corrupted
    $text = $text -replace "🕊️🙏", "🕊️🙏"

    #  EFree → · Free  (ReliquaryView unclaimed)
    $text = $text -replace " EFree", " · Free"

    # Catch any remaining "E/span>" or "E/div>" broken tags
    # These would be emoji-variation pairs where the variation selector went missing
    # Replace with a safe emoji
    $text = $text -replace "(?<=[^\x00-\x7F])E/span>", "️</span>"
    $text = $text -replace "(?<=[^\x00-\x7F])E/div>", "️</div>"

    if ($text -ne $original) {
        [System.IO.File]::WriteAllText($f.FullName, $text, [System.Text.Encoding]::UTF8)
        Write-Output "Fixed: $($f.Name)"
        $fixCount++
    }
}

Write-Output "`nTotal files fixed: $fixCount"