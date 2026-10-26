import Foundation

public let simpleVectorToolDefinitions: [[String: Any]] = [
    [
        "name": "simplevector_state",
        "description": "Returns the current state of SimpleVector: document title, sourceFormat (SVG/PDF), pageCount, currentPageIndex, totalElementsCount, pdfTextElementCount, modifiedPDFTextCount, signatureCount, oscInPort, apiPort, version.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simplevector_pages",
        "description": "Returns the complete JSON list of pages and vector elements (text blocks, extracted PDF text lines, signatures, shapes, paths, stamps).",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simplevector_help",
        "description": "Returns the full HTTP API, MCP tool reference, and OSC address map for SimpleVector.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simplevector_open",
        "description": "Opens an SVG or PDF file by path or loads the built-in multi-page contract & stage plot demo.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Absolute path to an .svg or .pdf file"],
                "demo": ["type": "boolean", "description": "When true, loads the synthetic 3-page contract & stage plot document"],
            ],
        ],
    ],
    [
        "name": "simplevector_edit_text",
        "description": "Edits an existing PDF/SVG text element (by 1-based element index or matching substring) or adds a new text block to the specified page.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "page": ["type": "integer", "description": "1-based page number (defaults to current page)"],
                "match": ["type": "string", "description": "Substring of an existing text element to replace (optional)"],
                "text": ["type": "string", "description": "New text content"],
                "x": ["type": "number", "description": "Optional X position in points for new text"],
                "y": ["type": "number", "description": "Optional Y position in points for new text"],
                "fontSize": ["type": "number", "description": "Optional font size in points"],
            ],
            "required": ["text"],
        ],
    ],
    [
        "name": "simplevector_sign",
        "description": "Places a calligraphic signature (and optional approval stamp) on the target page.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "page": ["type": "integer", "description": "1-based page number (defaults to current page)"],
                "signer": ["type": "string", "description": "Signer name"],
                "x": ["type": "number", "description": "Center X coordinate in page points"],
                "y": ["type": "number", "description": "Center Y coordinate in page points"],
                "stamp": ["type": "string", "enum": ["approved", "signed", "stagePlot", "confidential", "draft"], "description": "Optional stamp to add"],
            ],
        ],
    ],
    [
        "name": "simplevector_add_page",
        "description": "Adds a new blank page or duplicates a page in multipage mode.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "format": ["type": "string", "enum": ["A4 Portrait", "A4 Paysage", "A3 Paysage", "US Letter", "16:9 Régie"], "description": "Page format preset"],
                "duplicate": ["type": "boolean", "description": "When true, duplicates the current page"],
            ],
        ],
    ],
    [
        "name": "simplevector_export",
        "description": "Saves or exports the document to PDF (multi-page vector), SVG, or PNG.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "outputPath": ["type": "string", "description": "Destination file path (.pdf, .svg, or .png)"],
                "format": ["type": "string", "enum": ["pdf", "svg", "png"], "description": "Export format (inferred from extension if omitted)"],
            ],
            "required": ["outputPath"],
        ],
    ],
    [
        "name": "simplevector_snapshot",
        "description": "Captures the SimpleVector window as a PNG image ('single', 'multipage', or 'grid').",
        "inputSchema": [
            "type": "object",
            "properties": [
                "view": ["type": "string", "enum": ["single", "multipage", "grid"], "description": "Optional view mode"],
            ],
        ],
    ],
]
