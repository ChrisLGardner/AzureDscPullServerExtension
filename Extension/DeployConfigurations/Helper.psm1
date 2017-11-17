function Get-Ast {
    [CmdletBinding()]
    param (
        $path
    )

    $tokens = $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseInput(
        (Get-Content $path -Raw),
        $path,
        [Ref]$tokens,
        [Ref]$parseErrors
    )
}
