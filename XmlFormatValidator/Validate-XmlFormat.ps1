<#
.SYNOPSIS
    Validates that a file is well-formed XML. Does not validate the path
    strings between tags and never connects to a storage account.

.DESCRIPTION
    Runs in two phases. Phase 2 is skipped if Phase 1 reports any issues -
    fix the structural problems first and re-run.

      Phase 1 - Well-formedness pre-scan.
        Reports every issue in a single pass:
          - Unpaired / unclosed / mismatched / cross-nested tags
          - Closing tags with no matching open
          - Stray '<' in text or attribute values (must use '&lt;')
          - Attributes missing '=', quotes, or value
          - Unclosed start tags ('<a' with no '>'), comments ('<!--' with
            no '-->'), CDATA sections ('<![CDATA[' with no ']]>'), or
            processing instructions ('<?' with no '?>')
          - Empty / unnamed tags

      Phase 2 - System.Xml.XmlReader pass (stops at the first violation).
        Catches subtler XML rules the Phase 1 scanner does not enforce:
          - '--' inside a comment
          - Duplicate attribute names on the same element
          - Prohibited DTD / external entity references
          - Invalid characters in tag or attribute names
          - Bad text encoding / BOM mismatches
        Configured with ConformanceLevel.Fragment so files with multiple
        top-level siblings (e.g. Data Box export XML's <BlobList> +
        <AzureFileList>) are accepted.

    What is NOT checked:
      - Text content between tags. Paths, names, IDs, whitespace - out of scope.
      - Schema. No opinion on which elements/attributes should exist.
      - Network / storage. No socket is ever opened.

.PARAMETER XmlPath
    Path to the XML file to validate.

.EXAMPLE
    .\Validate-XmlFormat.ps1 -XmlPath .\some-file.xml

.NOTES
    Exit code 0 = well-formed XML.
    Exit code 1 = the file is invalid, empty, or unreadable.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $XmlPath
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# XmlSyntaxScanner class (Phase 1 implementation)
# ============================================================================
# A character-by-character scanner that reports every well-formedness
# issue in a single pass. XmlReader (used in Phase 2) is a streaming parser
# that throws on the first violation, so a file with N unclosed tags would
# require N runs to discover them all. This scanner reports them all at once.
class XmlSyntaxScanner {
    hidden [string] $Raw
    hidden [int]    $Pos
    hidden [int]    $Line
    hidden [int]    $Col
    [System.Collections.Generic.List[pscustomobject]] $Issues
    hidden [System.Collections.Generic.Stack[pscustomobject]] $Stack

    XmlSyntaxScanner([string] $raw) {
        $this.Raw    = $raw
        $this.Pos    = 0
        $this.Line   = 1
        $this.Col    = 1
        $this.Issues = [System.Collections.Generic.List[pscustomobject]]::new()
        $this.Stack  = [System.Collections.Generic.Stack[pscustomobject]]::new()
    }

    hidden [void] Advance() {
        if ($this.Pos -lt $this.Raw.Length) {
            if ($this.Raw[$this.Pos] -eq "`n") { $this.Line++; $this.Col = 1 }
            else { $this.Col++ }
            $this.Pos++
        }
    }

    hidden [void] AdvanceN([int] $count) {
        for ($k = 0; $k -lt $count; $k++) { $this.Advance() }
    }

    hidden [bool] StartsWith([string] $s) {
        if ($this.Pos + $s.Length -gt $this.Raw.Length) { return $false }
        return $this.Raw.Substring($this.Pos, $s.Length) -ceq $s
    }

    hidden [bool] IsNameStartChar([char] $c) {
        return ($c -ge [char]'A' -and $c -le [char]'Z') -or
               ($c -ge [char]'a' -and $c -le [char]'z') -or
               $c -eq [char]'_' -or $c -eq [char]':'
    }

    hidden [bool] IsNameChar([char] $c) {
        return $this.IsNameStartChar($c) -or
               ($c -ge [char]'0' -and $c -le [char]'9') -or
               $c -eq [char]'-' -or $c -eq [char]'.'
    }

    hidden [string] ReadName() {
        $start = $this.Pos
        while ($this.Pos -lt $this.Raw.Length -and $this.IsNameChar($this.Raw[$this.Pos])) {
            $this.Advance()
        }
        return $this.Raw.Substring($start, $this.Pos - $start)
    }

    hidden [void] SkipWhitespace() {
        while ($this.Pos -lt $this.Raw.Length) {
            $c = $this.Raw[$this.Pos]
            if ($c -eq ' ' -or $c -eq "`t" -or $c -eq "`r" -or $c -eq "`n") { $this.Advance() }
            else { break }
        }
    }

    # Advance until past the next occurrence of $s. Returns $true if found,
    # $false if not (in which case Pos is left at end of input).
    hidden [bool] AdvancePast([string] $s) {
        $idx = $this.Raw.IndexOf($s, $this.Pos)
        if ($idx -lt 0) {
            while ($this.Pos -lt $this.Raw.Length) { $this.Advance() }
            return $false
        }
        $target = $idx + $s.Length
        while ($this.Pos -lt $target) { $this.Advance() }
        return $true
    }

    hidden [void] AddIssue([int] $line, [int] $col, [string] $msg) {
        $this.Issues.Add([pscustomobject]@{
            Line = $line; Column = $col; Issue = $msg
        }) | Out-Null
    }

    [void] Scan() {
        while ($this.Pos -lt $this.Raw.Length) {
            $c = $this.Raw[$this.Pos]
            if ($c -eq '<') { $this.HandleOpenAngle() }
            else { $this.Advance() }
        }
        # Anything still on the stack is an unclosed tag.
        while ($this.Stack.Count -gt 0) {
            $top = $this.Stack.Pop()
            $this.AddIssue($top.Line, $top.Column,
                "Unclosed tag '<$($top.Name)>' (no matching '</$($top.Name)>' before end of file)")
        }
    }

    hidden [void] HandleOpenAngle() {
        $startLine = $this.Line
        $startCol  = $this.Col

        if ($this.StartsWith('<!--')) {
            $this.AdvanceN(4)
            if (-not $this.AdvancePast('-->')) {
                $this.AddIssue($startLine, $startCol, "Unclosed XML comment (missing '-->')")
            }
            return
        }
        if ($this.StartsWith('<![CDATA[')) {
            $this.AdvanceN(9)
            if (-not $this.AdvancePast(']]>')) {
                $this.AddIssue($startLine, $startCol, "Unclosed CDATA section (missing ']]>')")
            }
            return
        }
        if ($this.StartsWith('<!')) {
            # DOCTYPE or other declaration. XmlReader in Phase 2 prohibits DTDs;
            # here we just consume up to the next '>' loosely.
            $this.AdvanceN(2)
            if (-not $this.AdvancePast('>')) {
                $this.AddIssue($startLine, $startCol, "Unclosed '<!...' declaration (missing '>')")
            }
            return
        }
        if ($this.StartsWith('<?')) {
            $this.AdvanceN(2)
            if (-not $this.AdvancePast('?>')) {
                $this.AddIssue($startLine, $startCol, "Unclosed processing instruction (missing '?>')")
            }
            return
        }
        if ($this.StartsWith('</')) {
            $this.HandleEndTag($startLine, $startCol)
            return
        }
        # Plain '<': must be followed by a name-start character to begin an element.
        if ($this.Pos + 1 -lt $this.Raw.Length -and $this.IsNameStartChar($this.Raw[$this.Pos + 1])) {
            $this.HandleStartTag($startLine, $startCol)
            return
        }
        $this.AddIssue($startLine, $startCol,
            "Stray '<' character (must begin a tag, comment, CDATA, or processing instruction; use '&lt;' for a literal '<')")
        $this.Advance()
    }

    hidden [void] HandleEndTag([int] $startLine, [int] $startCol) {
        $this.AdvanceN(2)  # past '</'
        $name = $this.ReadName()
        if ([string]::IsNullOrEmpty($name)) {
            $this.AddIssue($startLine, $startCol, "Invalid end tag (missing tag name after '</')")
            [void]$this.AdvancePast('>')
            return
        }
        $this.SkipWhitespace()
        if ($this.Pos -ge $this.Raw.Length -or $this.Raw[$this.Pos] -ne '>') {
            $this.AddIssue($this.Line, $this.Col,
                "Invalid end tag '</$name' - expected '>' to close the tag")
            [void]$this.AdvancePast('>')
            return
        }
        $this.Advance()  # past '>'

        if ($this.Stack.Count -eq 0) {
            $this.AddIssue($startLine, $startCol,
                "Closing tag '</$name>' has no matching open tag")
            return
        }

        $top = $this.Stack.Peek()
        if ($top.Name -ceq $name) {
            [void]$this.Stack.Pop()
            return
        }

        # Mismatch. See if a matching opener exists deeper in the stack; if so,
        # everything above it is an unclosed tag. If not, just flag the mismatch.
        $items = @($this.Stack)  # foreach on Stack yields LIFO (top first)
        $matchAt = -1
        for ($k = 0; $k -lt $items.Length; $k++) {
            if ($items[$k].Name -ceq $name) { $matchAt = $k; break }
        }
        if ($matchAt -ge 0) {
            for ($k = 0; $k -lt $matchAt; $k++) {
                $unclosed = $this.Stack.Pop()
                $this.AddIssue($unclosed.Line, $unclosed.Column,
                    "Unclosed tag '<$($unclosed.Name)>' (the next closing tag was '</$name>' on line $startLine)")
            }
            [void]$this.Stack.Pop()
        } else {
            $this.AddIssue($startLine, $startCol,
                "Mismatched closing tag '</$name>' - expected '</$($top.Name)>' (opened on line $($top.Line))")
        }
    }

    hidden [void] HandleStartTag([int] $startLine, [int] $startCol) {
        $this.Advance()  # past '<'
        $name = $this.ReadName()
        if ([string]::IsNullOrEmpty($name)) {
            $this.AddIssue($startLine, $startCol, "Invalid start tag (missing tag name after '<')")
            [void]$this.AdvancePast('>')
            return
        }

        $closed     = $false
        $selfClose  = $false
        $structural = $true

        while ($this.Pos -lt $this.Raw.Length -and $structural) {
            $this.SkipWhitespace()
            if ($this.Pos -ge $this.Raw.Length) { break }

            $c = $this.Raw[$this.Pos]

            if ($c -eq '>') {
                $this.Advance()
                $closed = $true
                break
            }
            if ($c -eq '/') {
                if ($this.Pos + 1 -lt $this.Raw.Length -and $this.Raw[$this.Pos + 1] -eq '>') {
                    $this.AdvanceN(2)
                    $selfClose = $true
                    $closed    = $true
                    break
                }
                $this.AddIssue($this.Line, $this.Col,
                    "Unexpected '/' in tag '<$name>' (self-closing form must be '/>')")
                $structural = $false
                [void]$this.AdvancePast('>')
                break
            }
            if ($this.IsNameStartChar($c)) {
                $attrLine = $this.Line; $attrCol = $this.Col
                $attrName = $this.ReadName()
                $this.SkipWhitespace()
                if ($this.Pos -ge $this.Raw.Length -or $this.Raw[$this.Pos] -ne '=') {
                    $this.AddIssue($attrLine, $attrCol,
                        "Attribute '$attrName' on '<$name>' is missing '=' before its value")
                    $structural = $false
                    [void]$this.AdvancePast('>')
                    break
                }
                $this.Advance()  # past '='
                $this.SkipWhitespace()
                if ($this.Pos -ge $this.Raw.Length -or
                    ($this.Raw[$this.Pos] -ne '"' -and $this.Raw[$this.Pos] -ne "'")) {
                    $this.AddIssue($this.Line, $this.Col,
                        "Attribute '$attrName' on '<$name>' must have a quoted value (use `" or ')")
                    $structural = $false
                    [void]$this.AdvancePast('>')
                    break
                }
                $quote     = $this.Raw[$this.Pos]
                $quoteLine = $this.Line
                $quoteCol  = $this.Col
                $this.Advance()  # past opening quote
                $valueClosed = $false
                while ($this.Pos -lt $this.Raw.Length) {
                    $vc = $this.Raw[$this.Pos]
                    if ($vc -eq $quote) {
                        $this.Advance()
                        $valueClosed = $true
                        break
                    }
                    if ($vc -eq '<') {
                        $this.AddIssue($this.Line, $this.Col,
                            "'<' is not allowed inside an attribute value (use '&lt;')")
                    }
                    $this.Advance()
                }
                if (-not $valueClosed) {
                    $this.AddIssue($quoteLine, $quoteCol,
                        "Unclosed attribute value for '$attrName' on '<$name>' (missing closing $quote)")
                    $structural = $false
                    break
                }
                continue
            }
            $this.AddIssue($this.Line, $this.Col,
                "Unexpected character '$c' inside tag '<$name>'")
            $structural = $false
            [void]$this.AdvancePast('>')
            break
        }

        if ($structural -and -not $closed) {
            $this.AddIssue($startLine, $startCol,
                "Unclosed start tag '<$name' (missing closing '>')")
            return
        }

        if ($structural -and -not $selfClose) {
            $this.Stack.Push([pscustomobject]@{
                Name = $name; Line = $startLine; Column = $startCol
            })
        }
    }
}

# ============================================================================
# Issue accumulator
# ============================================================================

$issues = New-Object System.Collections.Generic.List[object]

function Add-Issue {
    param(
        [int]    $Line,
        [int]    $Column,
        [string] $Issue
    )
    $script:issues.Add([pscustomobject]@{
        Line   = $Line
        Column = $Column
        Issue  = $Issue
    }) | Out-Null
}

# ============================================================================
# Read the file
# ============================================================================

if (-not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) {
    throw "XML file not found: $XmlPath"
}

try {
    $raw = Get-Content -LiteralPath $XmlPath -Raw -ErrorAction Stop
} catch {
    throw "Failed to read XML file '$XmlPath': $($_.Exception.Message)"
}

if ([string]::IsNullOrWhiteSpace($raw)) {
    Write-Host ''
    Write-Host "ERROR: XML file is empty or contains only whitespace: $XmlPath" -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ============================================================================
# Phase 1: well-formedness pre-scan
# ============================================================================

$scanner = [XmlSyntaxScanner]::new($raw)
$scanner.Scan()

foreach ($wf in $scanner.Issues) {
    Add-Issue -Line $wf.Line -Column $wf.Column -Issue $wf.Issue
}

$wfErrorCount = $scanner.Issues.Count

# ============================================================================
# Phase 2: XmlReader pass for subtler XML rules
# ----------------------------------------------------------------------------
# Runs only if Phase 1 is clean. Configured with ConformanceLevel.Fragment
# so files with multiple top-level siblings (e.g. Data Box export XML's
# <BlobList> + <AzureFileList>) are accepted - we are checking format, not
# single-root structure. DTDs and external entities are disabled
# (XXE / billion-laughs safety).
# ============================================================================

$parseError = $null

if ($wfErrorCount -eq 0) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.ConformanceLevel = [System.Xml.ConformanceLevel]::Fragment
    $settings.DtdProcessing    = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver      = $null
    $settings.IgnoreWhitespace = $false
    $settings.IgnoreComments   = $false

    $stringReader = New-Object System.IO.StringReader($raw)
    try {
        $xmlReader = [System.Xml.XmlReader]::Create($stringReader, $settings)
    } catch {
        $stringReader.Dispose()
        throw "Failed to initialize XML reader: $($_.Exception.Message)"
    }

    try {
        # Just drain the reader. We do not inspect node contents - this pass
        # only matters for whether the XML parser itself accepts the file.
        while ($xmlReader.Read()) { }
    }
    catch [System.Xml.XmlException] {
        $parseError = $_.Exception
        Add-Issue -Line $parseError.LineNumber -Column $parseError.LinePosition `
            -Issue "XML parse error: $($parseError.Message)"
    }
    finally {
        if ($xmlReader) { $xmlReader.Dispose() }
        $stringReader.Dispose()
    }
}

# ============================================================================
# Report
# ============================================================================

Write-Host ''
if ($issues.Count -eq 0) {
    Write-Host "OK: '$XmlPath' is well-formed XML." -ForegroundColor Green
    Write-Host ''
    exit 0
}

$ordered = $issues | Sort-Object Line, Column

$ordered |
    Format-Table -AutoSize -Wrap Line, Column, Issue |
    Out-String -Width 4096 |
    Write-Host

Write-Host ("Errors : {0}" -f $issues.Count) -ForegroundColor Red
Write-Host ''

if ($wfErrorCount -gt 0) {
    Write-Host "Note: well-formedness errors were found in Phase 1; the deeper XmlReader pass was skipped. Fix the errors above and re-run." -ForegroundColor Yellow
    Write-Host ''
}
elseif ($parseError) {
    Write-Host "Note: a fatal XML parse error stopped Phase 2. Issues that occur after line $($parseError.LineNumber) in the file were NOT checked." -ForegroundColor Yellow
    Write-Host ''
}

exit 1
