#!/usr/bin/env python3
"""Build the three sample invoice PDFs of the "Read an invoice" tutorial.

The PDFs in ../pdf/ are committed, so a reader of the course never runs this.
Run it only when you change an invoice.

    python3 -m venv .venv && .venv/bin/pip install reportlab
    .venv/bin/python build_pdfs.py

Two rules keep the files small and readable for a model:

* Only the 14 standard PDF fonts (Helvetica, Times). No font is embedded, so
  each file stays near 6 kB instead of 200 kB.
* Real text, never an image. Every number on the page is in the text layer.
"""

import os
import shutil
import subprocess

from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import A4, LETTER
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pdf")

GREY = colors.HexColor("#6a6f78")
DARK = colors.HexColor("#17181c")
RULE = colors.HexColor("#c9ccd2")


def style(name, **kw):
    kw.setdefault("fontName", "Helvetica")
    kw.setdefault("fontSize", 8.5)
    kw.setdefault("leading", kw["fontSize"] * 1.35)
    kw.setdefault("textColor", DARK)
    return ParagraphStyle(name, **kw)


def build(path, pagesize, story, margin=16 * mm):
    doc = BaseDocTemplate(
        path,
        pagesize=pagesize,
        leftMargin=margin,
        rightMargin=margin,
        topMargin=margin,
        bottomMargin=14 * mm,
    )
    frame = Frame(
        doc.leftMargin,
        doc.bottomMargin,
        doc.width,
        doc.height,
        leftPadding=0,
        rightPadding=0,
        topPadding=0,
        bottomPadding=0,
    )
    doc.addPageTemplates([PageTemplate(id="p", frames=[frame])])
    doc.build(story)
    print(os.path.normpath(path), os.path.getsize(path), "bytes")


def kv_table(rows, widths, label_style, value_style):
    data = [[Paragraph(k, label_style), Paragraph(v, value_style)] for k, v in rows]
    t = Table(data, colWidths=widths)
    t.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 1.2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1.2),
            ]
        )
    )
    return t


# ---------------------------------------------------------------------------
# 1. FerroTek — a clean UK invoice. The one the course reads first.
# ---------------------------------------------------------------------------
def ferrotek():
    accent = colors.HexColor("#1b3a5c")
    head = style("h", fontName="Helvetica-Bold", fontSize=18, textColor=accent)
    tag = style("t", fontSize=7, textColor=GREY)
    right = style("r", alignment=TA_RIGHT, fontSize=8, textColor=colors.HexColor("#4a4f58"))
    lbl = style("l", fontSize=6.5, textColor=colors.HexColor("#8a8f98"))
    body = style("b", fontSize=9)
    k = style("k", fontSize=8.5, textColor=GREY)
    v = style("v", fontName="Helvetica-Bold", fontSize=8.5)
    title = style("ti", fontName="Helvetica-Bold", fontSize=16, textColor=DARK)
    part = style("p", fontSize=7, textColor=GREY)
    cell = style("c", fontSize=8.5)
    fine = style("f", fontSize=7, textColor=GREY, leading=10)

    s = []
    top = Table(
        [
            [
                [Paragraph("FerroTek", head), Paragraph("COMPONENTS AND DRIVE SYSTEMS", tag)],
                Paragraph(
                    "FerroTek Components Ltd<br/>Unit 14, Brackmills Industrial Estate<br/>"
                    "Northampton NN4 7BW<br/>United Kingdom<br/>VAT GB 421 8890 33",
                    right,
                ),
            ]
        ],
        colWidths=[95 * mm, 83 * mm],
    )
    top.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("LINEBELOW", (0, 0), (-1, 0), 1.6, accent),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 7),
            ]
        )
    )
    s += [top, Spacer(1, 9 * mm), Paragraph("Invoice", title), Spacer(1, 5 * mm)]

    meta = [
        ("Invoice number", "FT-2026-04417"),
        ("Invoice date", "14 July 2026"),
        ("Due date", "13 August 2026"),
        ("Purchase order", "PO-4500198231"),
        ("Customer account", "MER-0042"),
        ("Currency", "GBP"),
    ]
    cols = Table(
        [
            [
                [
                    Paragraph("INVOICE TO", lbl),
                    Spacer(1, 1.5 * mm),
                    Paragraph(
                        "Meridian Field Services Ltd<br/>Parts Receiving, Gate 3<br/>"
                        "88 Halton Road<br/>Leeds LS9 8AB<br/>United Kingdom",
                        body,
                    ),
                ],
                kv_table(meta, [32 * mm, 40 * mm], k, v),
            ]
        ],
        colWidths=[88 * mm, 90 * mm],
    )
    cols.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    s += [cols, Spacer(1, 8 * mm)]

    lines = [
        ("1", "Servo gearbox SG-40, ratio 1:25", "Part no. FT-SG40-25", "2", "pcs", "412.00", "824.00"),
        ("2", "Sealed bearing unit, 40 mm bore", "Part no. FT-BU40-S", "12", "pcs", "28.50", "342.00"),
        ("3", "Hydraulic hose assembly, 1.8 m", "Part no. FT-HH18", "6", "pcs", "64.75", "388.50"),
        ("4", "Drive belt, toothed, 1250 mm", "Part no. FT-DB1250", "10", "pcs", "19.30", "193.00"),
        ("5", "On-site support, senior engineer", "Service, 4 hours on site", "4", "hrs", "86.00", "344.00"),
    ]
    hdr = style("th", fontName="Helvetica-Bold", fontSize=6.8, textColor=colors.white)
    data = [[Paragraph(x, hdr) for x in ("#", "DESCRIPTION", "QTY", "UNIT", "UNIT PRICE", "AMOUNT")]]
    for no, desc, pn, qty, uom, price, amount in lines:
        data.append(
            [
                Paragraph(no, cell),
                [Paragraph(desc, cell), Paragraph(pn, part)],
                Paragraph(qty, cell),
                Paragraph(uom, cell),
                Paragraph(price, cell),
                Paragraph(amount, cell),
            ]
        )
    t = Table(data, colWidths=[9 * mm, 76 * mm, 15 * mm, 16 * mm, 28 * mm, 34 * mm])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), accent),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (2, 0), (3, -1), "CENTER"),
                ("ALIGN", (4, 0), (-1, -1), "RIGHT"),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("LINEBELOW", (0, 1), (-1, -1), 0.4, RULE),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f6f7f9")]),
            ]
        )
    )
    s += [t, Spacer(1, 5 * mm)]

    grand = style("g", fontName="Helvetica-Bold", fontSize=11, textColor=accent)
    sums = [
        (Paragraph("Subtotal", cell), Paragraph("2,091.50", cell)),
        (Paragraph("Delivery", cell), Paragraph("45.00", cell)),
        (Paragraph("VAT 20%", cell), Paragraph("427.30", cell)),
        (Paragraph("Total due (GBP)", grand), Paragraph("2,563.80", grand)),
    ]
    st = Table([list(r) for r in sums], colWidths=[52 * mm, 30 * mm], hAlign="RIGHT")
    st.setStyle(
        TableStyle(
            [
                ("ALIGN", (1, 0), (1, -1), "RIGHT"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 2.5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
                ("LINEABOVE", (0, 3), (-1, 3), 1.1, accent),
                ("TOPPADDING", (0, 3), (-1, 3), 6),
            ]
        )
    )
    s += [st, Spacer(1, 12 * mm)]
    s += [
        Paragraph(
            "<b>Payment terms:</b> net 30 days from the invoice date. Please quote the invoice "
            "number with your payment.<br/>Bank: Nationwide Commercial, sort code 07-14-22, "
            "account 88410275, IBAN GB29 NWBK 6016 1331 9268 19<br/>Registered in England and "
            "Wales, company number 04812277. Goods stay our property until they are paid in full.",
            fine,
        )
    ]
    build(os.path.join(OUT, "ferrotek.pdf"), A4, s)


# ---------------------------------------------------------------------------
# 2. Nordwind — the same facts, a German layout. Proves the schema travels.
# ---------------------------------------------------------------------------
def nordwind():
    ink = colors.HexColor("#111111")
    name = style("n", fontName="Times-Bold", fontSize=14, textColor=ink)
    sub = style("s", fontName="Times-Roman", fontSize=7.5, textColor=colors.HexColor("#555555"))
    body = style("b", fontName="Times-Roman", fontSize=9.5)
    k = style("k", fontName="Times-Roman", fontSize=8.5, textColor=colors.HexColor("#555555"))
    v = style("v", fontName="Times-Bold", fontSize=8.5)
    title = style("t", fontName="Times-Bold", fontSize=13)
    small = style("sm", fontName="Times-Roman", fontSize=7, textColor=colors.HexColor("#666666"))
    cell = style("c", fontName="Times-Roman", fontSize=9)
    art = style("a", fontName="Times-Roman", fontSize=7.2, textColor=colors.HexColor("#666666"))
    hdr = style("h", fontName="Times-Bold", fontSize=8)
    fine = style("f", fontName="Times-Roman", fontSize=7, textColor=colors.HexColor("#555555"), leading=10.5)

    s = []
    head = Table(
        [[[Paragraph("NORDWIND Industrietechnik GmbH", name),
           Paragraph("Antriebstechnik &#183; Hydraulik &#183; Ersatzteile", sub)]]],
        colWidths=[178 * mm],
    )
    head.setStyle(
        TableStyle(
            [
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("LINEBELOW", (0, 0), (-1, 0), 0.9, ink),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 6),
            ]
        )
    )
    s += [head, Spacer(1, 10 * mm)]

    meta = [
        ("Rechnungsnummer", "NW-2026-1188"),
        ("Rechnungsdatum", "03.08.2026"),
        ("Lieferdatum", "29.07.2026"),
        ("Kundennummer", "K-11940"),
        ("Bestellnummer", "PO-4500198247"),
        ("Ansprechpartner", "T. Bergmann"),
        ("USt-IdNr.", "DE 812 449 037"),
    ]
    addr = Table(
        [
            [
                [
                    Paragraph(
                        "Nordwind Industrietechnik GmbH &#183; Hafenstraße 47 &#183; 28217 Bremen",
                        small,
                    ),
                    Spacer(1, 3 * mm),
                    Paragraph(
                        "Meridian Field Services Ltd<br/>Wareneingang Tor 3<br/>88 Halton Road<br/>"
                        "LS9 8AB Leeds<br/>Vereinigtes Königreich",
                        body,
                    ),
                ],
                kv_table(meta, [36 * mm, 34 * mm], k, v),
            ]
        ],
        colWidths=[100 * mm, 78 * mm],
    )
    addr.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("LINEBELOW", (0, 0), (0, 0), 0.4, colors.HexColor("#999999")),
            ]
        )
    )
    s += [addr, Spacer(1, 10 * mm), Paragraph("Rechnung", title), Spacer(1, 2 * mm)]
    s += [
        Paragraph("Betrifft: Lieferung vom 29.07.2026, Lieferschein LS-77412", body),
        Spacer(1, 6 * mm),
    ]

    lines = [
        ("10", "Planetengetriebe PG-63, Übersetzung 1:40", "Art.-Nr. NW-PG63-40", "3", "Stk", "1.180,00", "3.540,00"),
        ("20", "Wellendichtring 55x72x8, FKM", "Art.-Nr. NW-WDR-5572", "40", "Stk", "6,45", "258,00"),
        ("30", "Hydraulikpumpe HP-22, 22 l/min", "Art.-Nr. NW-HP22", "1", "Stk", "2.310,50", "2.310,50"),
        ("40", "Kupplungsnabe, Bohrung 38 mm", "Art.-Nr. NW-KN38", "8", "Stk", "47,25", "378,00"),
        ("50", "Versand und Verpackung", "Versandpauschale, Palette", "1", "psch", "96,00", "96,00"),
    ]
    data = [[Paragraph(x, hdr) for x in ("Pos.", "Bezeichnung", "Menge", "Einheit", "Einzelpreis", "Betrag")]]
    for no, desc, pn, qty, uom, price, amount in lines:
        data.append(
            [
                Paragraph(no, cell),
                [Paragraph(desc, cell), Paragraph(pn, art)],
                Paragraph(qty, cell),
                Paragraph(uom, cell),
                Paragraph(price, cell),
                Paragraph(amount, cell),
            ]
        )
    t = Table(data, colWidths=[12 * mm, 74 * mm, 16 * mm, 18 * mm, 28 * mm, 30 * mm])
    t.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (2, 0), (3, -1), "CENTER"),
                ("ALIGN", (4, 0), (-1, -1), "RIGHT"),
                ("TOPPADDING", (0, 0), (-1, -1), 3.5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("LINEABOVE", (0, 0), (-1, 0), 0.9, ink),
                ("LINEBELOW", (0, 0), (-1, 0), 0.5, ink),
                ("LINEBELOW", (0, 1), (-1, -1), 0.4, colors.HexColor("#cccccc")),
            ]
        )
    )
    s += [t, Spacer(1, 5 * mm)]

    g = style("g", fontName="Times-Bold", fontSize=9.5)
    sums = [
        ("Zwischensumme", "6.582,50 EUR", cell),
        ("Skonto 2% bei Zahlung bis 13.08.2026", "-131,65 EUR", cell),
        ("Nettobetrag", "6.450,85 EUR", cell),
        ("MwSt. 19%", "1.225,66 EUR", cell),
        ("Gesamtbetrag", "7.676,51 EUR", g),
    ]
    st = Table(
        [[Paragraph(a, stl), Paragraph(b, stl)] for a, b, stl in sums],
        colWidths=[58 * mm, 26 * mm],
        hAlign="RIGHT",
    )
    st.setStyle(
        TableStyle(
            [
                ("ALIGN", (1, 0), (1, -1), "RIGHT"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                ("LINEABOVE", (0, 4), (-1, 4), 0.9, ink),
                ("LINEBELOW", (0, 4), (-1, 4), 1.6, ink),
                ("TOPPADDING", (0, 4), (-1, 4), 4),
                ("BOTTOMPADDING", (0, 4), (-1, 4), 4),
            ]
        )
    )
    s += [st, Spacer(1, 12 * mm)]

    foot = Table(
        [
            [
                Paragraph(
                    "<b>Zahlungsbedingungen</b><br/>30 Tage netto ohne Abzug.<br/>"
                    "2% Skonto bei Zahlung bis 13.08.2026.",
                    fine,
                ),
                Paragraph(
                    "<b>Bankverbindung</b><br/>Bremer Landesbank<br/>"
                    "IBAN DE44 2905 0000 1120 7744 81<br/>BIC BRLADE22XXX",
                    fine,
                ),
                Paragraph(
                    "<b>Registergericht</b><br/>Amtsgericht Bremen HRB 24 118<br/>"
                    "Geschäftsführer: A. Vosskamp<br/>Es gelten unsere AGB.",
                    fine,
                ),
            ]
        ],
        colWidths=[59 * mm, 59 * mm, 60 * mm],
    )
    foot.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (0, -1), 0),
                ("RIGHTPADDING", (-1, 0), (-1, -1), 0),
                ("LINEABOVE", (0, 0), (-1, 0), 0.4, colors.HexColor("#999999")),
                ("TOPPADDING", (0, 0), (-1, 0), 6),
            ]
        )
    )
    s += [foot]
    build(os.path.join(OUT, "nordwind.pdf"), A4, s)


# ---------------------------------------------------------------------------
# 3. Halvorsen — two pages, an ambiguous date, a negative line.
#    This is the invoice the validation lesson is built on.
# ---------------------------------------------------------------------------
def halvorsen():
    green = colors.HexColor("#2f6b3d")
    red = colors.HexColor("#a4341f")
    name = style("n", fontName="Helvetica-Bold", fontSize=14, textColor=colors.white)
    tag = style("t", fontSize=6.5, textColor=colors.HexColor("#cfe0d4"))
    doc = style("d", fontName="Helvetica-Bold", fontSize=12, textColor=colors.white, alignment=TA_RIGHT)
    lbl = style("l", fontSize=6.2, textColor=GREY)
    body = style("b", fontSize=8.5)
    bodyr = style("br", fontSize=8.5, alignment=TA_RIGHT)
    kk = style("kk", fontSize=6.2, textColor=GREY)
    vv = style("vv", fontName="Helvetica-Bold", fontSize=8.5)
    cell = style("c", fontSize=8.5)
    cellr = style("cr", fontSize=8.5, textColor=red)
    part = style("p", fontSize=7, textColor=GREY)
    hdr = style("h", fontName="Helvetica-Bold", fontSize=6.5, textColor=colors.HexColor("#33553c"))
    note = style("nt", fontSize=7.4, leading=11, textColor=colors.HexColor("#444444"))
    pf = style("pf", fontSize=6.8, textColor=colors.HexColor("#7a7a7a"))
    pfr = style("pfr", fontSize=6.8, textColor=colors.HexColor("#7a7a7a"), alignment=TA_RIGHT)

    width = 185 * mm

    def banner(right_text):
        b = Table(
            [
                [
                    [Paragraph("HALVORSEN BEARING AND DRIVE", name),
                     Paragraph("INDUSTRIAL BEARINGS AND POWER TRANSMISSION", tag)],
                    Paragraph(right_text, doc),
                ]
            ],
            colWidths=[120 * mm, 65 * mm],
        )
        b.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), green),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                    ("LEFTPADDING", (0, 0), (-1, -1), 8),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                    ("TOPPADDING", (0, 0), (-1, -1), 7),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ]
            )
        )
        return b

    def items(rows, negatives=()):
        data = [[Paragraph(x, hdr) for x in ("LINE", "ITEM", "QTY", "UOM", "UNIT PRICE", "EXTENDED")]]
        for no, desc, pn, qty, uom, price, amount in rows:
            st = cellr if no in negatives else cell
            data.append(
                [
                    Paragraph(no, cell),
                    [Paragraph(desc, cell), Paragraph(pn, part)],
                    Paragraph(qty, cell),
                    Paragraph(uom, cell),
                    Paragraph(price, st),
                    Paragraph(amount, st),
                ]
            )
        t = Table(data, colWidths=[12 * mm, 83 * mm, 15 * mm, 15 * mm, 28 * mm, 32 * mm])
        t.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#eef2ee")),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("ALIGN", (2, 0), (3, -1), "CENTER"),
                    ("ALIGN", (4, 0), (-1, -1), "RIGHT"),
                    ("TOPPADDING", (0, 0), (-1, -1), 4),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                    ("LEFTPADDING", (0, 0), (-1, -1), 5),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                    ("LINEABOVE", (0, 0), (-1, 0), 0.7, green),
                    ("LINEBELOW", (0, 0), (-1, 0), 0.6, RULE),
                    ("LINEBELOW", (0, 1), (-1, -1), 0.4, colors.HexColor("#dcdcdc")),
                ]
            )
        )
        return t

    def footer(page):
        f = Table(
            [[Paragraph("Halvorsen Bearing and Drive Inc. &#183; Invoice HB-88214", pf),
              Paragraph(page, pfr)]],
            colWidths=[120 * mm, 65 * mm],
        )
        f.setStyle(
            TableStyle(
                [
                    ("LEFTPADDING", (0, 0), (-1, -1), 0),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                    ("LINEABOVE", (0, 0), (-1, 0), 0.4, RULE),
                    ("TOPPADDING", (0, 0), (-1, 0), 5),
                ]
            )
        )
        return f

    s = [banner("INVOICE"), Spacer(1, 6 * mm)]

    addr = Table(
        [
            [
                [Paragraph("BILL TO", lbl), Spacer(1, 1.2 * mm),
                 Paragraph("Meridian Field Services Ltd<br/>Accounts Payable<br/>88 Halton Road<br/>"
                           "Leeds LS9 8AB<br/>United Kingdom", body)],
                [Paragraph("SHIP TO", lbl), Spacer(1, 1.2 * mm),
                 Paragraph("Meridian Field Services Ltd<br/>Parts Receiving, Gate 3<br/>88 Halton Road<br/>"
                           "Leeds LS9 8AB<br/>United Kingdom", body)],
                [Paragraph("REMIT TO", ParagraphStyle("lr", parent=lbl, alignment=TA_RIGHT)),
                 Spacer(1, 1.2 * mm),
                 Paragraph("Halvorsen Bearing and Drive Inc.<br/>2140 Commerce Parkway<br/>"
                           "Cleveland, OH 44115<br/>United States<br/>EIN 34-2891055", bodyr)],
            ]
        ],
        colWidths=[62 * mm, 62 * mm, 61 * mm],
    )
    addr.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (0, -1), 0),
                ("RIGHTPADDING", (-1, 0), (-1, -1), 0),
            ]
        )
    )
    s += [addr, Spacer(1, 6 * mm)]

    grid_cells = [
        ("INVOICE NO.", "HB-88214"),
        ("INVOICE DATE", "08/11/2026"),
        ("TERMS", "Net 45"),
        ("DUE DATE", "09/25/2026"),
        ("CUSTOMER PO", "PO-4500199003"),
        ("CURRENCY", "USD"),
    ]
    g = Table(
        [[[Paragraph(a, kk), Spacer(1, 0.8 * mm), Paragraph(b, vv)] for a, b in grid_cells]],
        colWidths=[width / 6.0] * 6,
    )
    g.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (-1, -1), 0.7, RULE),
                ("INNERGRID", (0, 0), (-1, -1), 0.7, RULE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    s += [g, Spacer(1, 6 * mm)]

    s += [
        items(
            [
                ("1", "Tapered roller bearing, TRB-32210", "Part HB-TRB32210", "24", "EA", "41.20", "988.80"),
                ("2", "Spherical roller bearing, SRB-22215", "Part HB-SRB22215", "6", "EA", "214.75", "1,288.50"),
                ("3", "Bearing puller set, 3-arm, hydraulic", "Part HB-PULL3H", "1", "EA", "385.00", "385.00"),
                ("4", "Lithium EP2 grease, 5 kg tub", "Part HB-GR-EP2-5", "12", "EA", "33.60", "403.20"),
                ("5", "Shaft seal kit SK-70", "Part HB-SK70", "15", "EA", "22.40", "336.00"),
                ("6", "Alignment laser, rental", "Service, 5 days on site", "5", "DAY", "120.00", "600.00"),
            ]
        ),
        Spacer(1, 4 * mm),
        Paragraph(
            "<i>Continued on page 2. Charges and adjustments follow. Do not pay from page 1.</i>", part
        ),
        Spacer(1, 8 * mm),
        footer("Page 1 of 2"),
        PageBreak(),
    ]

    s += [banner("INVOICE HB-88214 &#183; PAGE 2"), Spacer(1, 6 * mm)]
    s += [
        items(
            [
                ("7", "Expedited air freight, Cleveland to Leeds", "Waybill 016-88420713", "1", "EA", "487.65", "487.65"),
                ("8", "Volume discount, 5% on bearing lines 1 and 2", "Agreement MER-2026-VOL", "1", "EA", "-113.87", "-113.87"),
            ],
            negatives=("8",),
        ),
        Spacer(1, 6 * mm),
    ]

    grand = style("gg", fontName="Helvetica-Bold", fontSize=11.5, textColor=green)
    sums = [
        ("Merchandise, page 1", "4,001.50", cell, False),
        ("Charges and adjustments, page 2", "373.78", cell, False),
        ("Net amount", "4,375.28", cell, True),
        ("Sales tax, OH 8.0%", "350.02", cell, False),
        ("Total due (USD)", "4,725.30", grand, False),
    ]
    st = Table(
        [[Paragraph(a, stl), Paragraph(b, stl)] for a, b, stl, _ in sums],
        colWidths=[58 * mm, 30 * mm],
        hAlign="RIGHT",
    )
    st.setStyle(
        TableStyle(
            [
                ("ALIGN", (1, 0), (1, -1), "RIGHT"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 2.5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
                ("LINEABOVE", (0, 2), (-1, 2), 0.4, RULE),
                ("LINEABOVE", (0, 4), (-1, 4), 1.1, green),
                ("TOPPADDING", (0, 4), (-1, 4), 6),
            ]
        )
    )
    s += [st, Spacer(1, 8 * mm)]

    box = Table(
        [
            [
                Paragraph(
                    "<b>Payment.</b> Net 45 from the invoice date. Wire to Halvorsen Bearing and Drive Inc., "
                    "Huntington National Bank, routing 044000024, account 01998877541, reference HB-88214. "
                    "A 1.5% monthly service charge applies to a balance that is past due.<br/>"
                    "<b>Returns.</b> No return is accepted without an RMA number. The rental equipment on "
                    "line 6 must come back within 10 days of the rental end date. A late return is billed "
                    "at the daily rate.",
                    note,
                )
            ]
        ],
        colWidths=[width],
    )
    box.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (-1, -1), 0.7, RULE),
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#fafafa")),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ]
        )
    )
    s += [box, Spacer(1, 8 * mm), footer("Page 2 of 2")]

    build(os.path.join(OUT, "halvorsen.pdf"), LETTER, s, margin=12 * mm)


# ---------------------------------------------------------------------------
# 4. FerroTek delivery note — the document that is not an invoice.
#    It has no price on it anywhere, and it says so in words.
# ---------------------------------------------------------------------------
def delivery_note():
    accent = colors.HexColor("#1b3a5c")
    head = style("h", fontName="Helvetica-Bold", fontSize=18, textColor=accent)
    tag = style("t", fontSize=7, textColor=GREY)
    right = style("r", alignment=TA_RIGHT, fontSize=8, textColor=colors.HexColor("#4a4f58"))
    lbl = style("l", fontSize=6.5, textColor=colors.HexColor("#8a8f98"))
    body = style("b", fontSize=9)
    k = style("k", fontSize=8.5, textColor=GREY)
    v = style("v", fontName="Helvetica-Bold", fontSize=8.5)
    title = style("ti", fontName="Helvetica-Bold", fontSize=16, textColor=DARK)
    part = style("p", fontSize=7, textColor=GREY)
    cell = style("c", fontSize=8.5)
    warn = style("w", fontName="Helvetica-Bold", fontSize=9.5, textColor=colors.HexColor("#8a2c14"))
    fine = style("f", fontSize=7, textColor=GREY, leading=10)
    sign = style("sg", fontSize=8, textColor=GREY)

    s = []
    top = Table(
        [
            [
                [Paragraph("FerroTek", head), Paragraph("COMPONENTS AND DRIVE SYSTEMS", tag)],
                Paragraph(
                    "FerroTek Components Ltd<br/>Unit 14, Brackmills Industrial Estate<br/>"
                    "Northampton NN4 7BW<br/>United Kingdom<br/>VAT GB 421 8890 33",
                    right,
                ),
            ]
        ],
        colWidths=[95 * mm, 83 * mm],
    )
    top.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("LINEBELOW", (0, 0), (-1, 0), 1.6, accent),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 7),
            ]
        )
    )
    s += [top, Spacer(1, 9 * mm), Paragraph("Delivery note", title), Spacer(1, 5 * mm)]

    meta = [
        ("Delivery note no.", "DN-77118"),
        ("Despatch date", "11 July 2026"),
        ("Purchase order", "PO-4500198231"),
        ("Customer account", "MER-0042"),
        ("Carrier", "Palletways, job 8841207"),
        ("Packages", "3 of 3"),
    ]
    cols = Table(
        [
            [
                [
                    Paragraph("DELIVER TO", lbl),
                    Spacer(1, 1.5 * mm),
                    Paragraph(
                        "Meridian Field Services Ltd<br/>Parts Receiving, Gate 3<br/>"
                        "88 Halton Road<br/>Leeds LS9 8AB<br/>United Kingdom",
                        body,
                    ),
                ],
                kv_table(meta, [32 * mm, 45 * mm], k, v),
            ]
        ],
        colWidths=[88 * mm, 90 * mm],
    )
    cols.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    s += [cols, Spacer(1, 8 * mm)]

    banner = Table(
        [[Paragraph(
            "THIS IS A DELIVERY NOTE. IT IS NOT AN INVOICE. DO NOT PAY FROM THIS DOCUMENT. "
            "The invoice for this delivery is sent separately.", warn)]],
        colWidths=[178 * mm],
    )
    banner.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (-1, -1), 1.0, colors.HexColor("#8a2c14")),
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#fbf1ee")),
                ("LEFTPADDING", (0, 0), (-1, -1), 9),
                ("RIGHTPADDING", (0, 0), (-1, -1), 9),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ]
        )
    )
    s += [banner, Spacer(1, 7 * mm)]

    lines = [
        ("1", "Servo gearbox SG-40, ratio 1:25", "Part no. FT-SG40-25", "2", "2", "pcs"),
        ("2", "Sealed bearing unit, 40 mm bore", "Part no. FT-BU40-S", "12", "12", "pcs"),
        ("3", "Hydraulic hose assembly, 1.8 m", "Part no. FT-HH18", "6", "6", "pcs"),
        ("4", "Drive belt, toothed, 1250 mm", "Part no. FT-DB1250", "10", "10", "pcs"),
    ]
    hdr = style("th", fontName="Helvetica-Bold", fontSize=6.8, textColor=colors.white)
    data = [[Paragraph(x, hdr) for x in
             ("#", "DESCRIPTION", "ORDERED", "DELIVERED", "UNIT", "PACKAGE")]]
    for no, desc, pn, ordered, delivered, uom in lines:
        data.append(
            [
                Paragraph(no, cell),
                [Paragraph(desc, cell), Paragraph(pn, part)],
                Paragraph(ordered, cell),
                Paragraph(delivered, cell),
                Paragraph(uom, cell),
                Paragraph("1", cell),
            ]
        )
    t = Table(data, colWidths=[9 * mm, 84 * mm, 21 * mm, 23 * mm, 18 * mm, 23 * mm])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), accent),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (2, 0), (-1, -1), "CENTER"),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("LINEBELOW", (0, 1), (-1, -1), 0.4, RULE),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f6f7f9")]),
            ]
        )
    )
    s += [t, Spacer(1, 4 * mm)]
    s += [Paragraph(
        "Line 5 of the order, on-site support by a senior engineer, is a service. It is not "
        "delivered with these goods and it does not appear on this note.", part)]
    s += [Spacer(1, 14 * mm)]

    sg = Table(
        [
            [Paragraph("Received by (print name)", sign), Paragraph("Signature", sign),
             Paragraph("Date", sign)],
            [Spacer(1, 9 * mm), Spacer(1, 9 * mm), Spacer(1, 9 * mm)],
        ],
        colWidths=[70 * mm, 70 * mm, 38 * mm],
    )
    sg.setStyle(
        TableStyle(
            [
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("LINEBELOW", (0, 1), (-1, 1), 0.5, colors.HexColor("#999999")),
            ]
        )
    )
    s += [sg, Spacer(1, 10 * mm)]
    s += [Paragraph(
        "Check the goods before you sign. Report damage or a short delivery within 3 working "
        "days, quoting the delivery note number.<br/>FerroTek Components Ltd, registered in "
        "England and Wales, company number 04812277.", fine)]

    build(os.path.join(OUT, "ferrotek-delivery-note.pdf"), A4, s)


def scan():
    """Rasterize ferrotek.pdf into an image-only PDF with no text layer.

    This is the "somebody scanned the paper" case. Lesson 5 uses it to find where
    a small model stops being good enough, so it has to be a real scan: nothing
    to extract, only pixels.

    Needs ghostscript (`brew install ghostscript`). Skipped with a message when it
    is missing, because the other four PDFs do not need it.
    """
    src = os.path.join(OUT, "ferrotek.pdf")
    dst = os.path.join(OUT, "ferrotek-scan.pdf")

    if shutil.which("gs") is None:
        print("gs not found, skipping ferrotek-scan.pdf")
        return

    subprocess.run(
        ["gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pdfimage24", "-r200",
         "-sOutputFile=" + dst, src],
        check=True,
    )
    print(os.path.normpath(dst), os.path.getsize(dst), "bytes")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    ferrotek()
    nordwind()
    halvorsen()
    delivery_note()
    scan()
