# XML Format Validator

A generic XML well-formedness checker. Answers one question: **is this a
valid XML file?** It does not validate the path strings between tags and
never connects to a storage account.

## Usage

Requires Windows PowerShell 5.1+ or PowerShell 7+. No external modules.

```powershell
.\Validate-XmlFormat.ps1 -XmlPath <path to an xml input file>
```

Exit code `0` = well-formed XML. Exit code `1` = the file is invalid, empty, or unreadable.

## What is checked

The script runs in two phases. Phase 2 is skipped if Phase 1 reports any
issues — fix the structural problems first and re-run.

**Phase 1 — well-formedness pre-scan** (custom tokenizer, reports **every**
issue in one pass):

- Unpaired / unclosed / mismatched / cross-nested tags
- Closing tags with no matching open
- Stray `<` in text or attribute values (must use `&lt;`)
- Attributes missing `=`, quotes, or value
- Unclosed start tags (`<a` with no `>`), comments (`<!--` with no `-->`), CDATA sections (`<![CDATA[` with no `]]>`), or processing instructions (`<?` with no `?>`)
- Empty / unnamed tags

**Phase 2 — `System.Xml.XmlReader` pass** (stops at the first violation):

- `--` inside a comment
- Duplicate attribute names on the same element
- Prohibited DTD / external entity references
- Invalid characters in tag or attribute names
- Bad text encoding / BOM mismatches

Configured with `ConformanceLevel.Fragment`, so files with multiple
top-level siblings (e.g. `<BlobList>` + `<AzureFileList>`) are accepted.

## What is NOT checked

- **Text content between tags.** Paths, names, IDs, whitespace — out of scope.
- **Schema.** No opinion on which elements/attributes should exist.
- **Network / storage.** No socket is ever opened to validate storage account's content.

## Samples

| File | Purpose | Expected |
| ---- | ------- | -------- |
| `sample0.xml` | Clean Data-Box-style XML with two top-level siblings. | exit 0 |
| `negative-phase1.xml` | Single file exercising every Phase 1 category at once — proves Phase 1 reports them all in one pass. | exit 1, many Phase 1 errors, Phase 2 skipped |
| `negative-phase2/duplicate-attribute.xml` | Same attribute name twice on one element. | exit 1, Phase 2: `'x' is a duplicate attribute name` |
| `negative-phase2/double-hyphen-in-comment.xml` | `--` inside a comment. | exit 1, Phase 2: `XML comment cannot contain '--'` |
| `negative-phase2/cdata-end-in-text.xml` | Literal `]]>` in element content. | exit 1, Phase 2: `']]>' is not allowed in character data` |
| `negative-phase2/undefined-entity.xml` | Reference to an undeclared entity. | exit 1, Phase 2: `Reference to undeclared entity 'undefined'` |

Phase 2 violations each get their own file because `XmlReader` halts on
the first one it sees.

### Example runs

**Positive — `sample0.xml`:**

```powershell
.\Validate-XmlFormat.ps1 -XmlPath .\sample0.xml
```

```
OK: '.\sample0.xml' is well-formed XML.
```

**Phase 1 negative — `negative-phase1.xml`:**

```powershell
.\Validate-XmlFormat.ps1 -XmlPath .\negative-phase1.xml
```

```
Line Column Issue
---- ------ -----
  23     11 Stray '<' character (must begin a tag, comment, CDATA, or processing instruction; use '&lt;' for a literal '<')
  ... (other entries omitted) ...
  50      3 Unclosed tag '<Unclosed>' (the next closing tag was '</Root>' on line 52)

Errors : 12

Note: well-formedness errors were found in Phase 1; the deeper XmlReader pass was skipped. Fix the errors above and re-run.
```

**Phase 2 negative — `negative-phase2/cdata-end-in-text.xml`:**

```powershell
.\Validate-XmlFormat.ps1 -XmlPath .\negative-phase2\cdata-end-in-text.xml
```

```
Line Column Issue
---- ------ -----
  12     21 XML parse error: ']]>' is not allowed in character data. Line 12, position 21.

Errors : 1

Note: a fatal XML parse error stopped Phase 2. Issues that occur after line 12 in the file were NOT checked.
```
