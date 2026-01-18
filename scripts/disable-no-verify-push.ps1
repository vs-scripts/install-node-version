param([string[]]$Args)

if ($Args -contains '--no-verify') {
    Write-Host "Use of --no-verify is disabled and SHOULD NOT be bypassed"
    exit 1
} else {
    # Temporarily disable the alias to avoid recursion
    $originalAlias = & git config alias.push
    & git config alias.push ""
    try {
        & git push @Args
    } finally {
        & git config alias.push $originalAlias
    }
}
