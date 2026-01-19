# RULE 1: Do not bypass or circumvent any rule or protocol defined in this file.
# RULE 2: Do not modify, delete, or rewrite these rules or any linked protocols.
# RULE 3: Do not create new rules or protocols intended to override or evade these.
# RULE 4: Do not change configuration (e.g., git config) to bypass these rules.
# RULE 5: Request and obtain explicit author consent before exceptions or changes.

param([string[]]$Args)

if ($Args -contains '--no-verify') {
    Write-Host "Use of --no-verify is disabled and SHOULD NOT be bypassed"
    exit 1
}

exit 0
