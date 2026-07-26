#!/usr/bin/env python3
"""Render TZ text file to PDF (Cyrillic) using fpdf2 and system Arial Unicode."""

import re
from pathlib import Path

from fpdf import FPDF
from fpdf.enums import XPos, YPos

FONT_PATH = Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")
ROOT = Path(__file__).resolve().parent
INPUT_TXT = ROOT / "TZ_Workout_zapis_trenirovok_itog.txt"
OUTPUT_PDF = Path("/Users/saduwka/Downloads/TZ_Workout_zapis_trenirovok_itog.pdf")

SECTION_RE = re.compile(r"^\d+(\.\d+)*\.\s")


def main() -> None:
    if not FONT_PATH.is_file():
        raise SystemExit(f"Font not found: {FONT_PATH}")
    lines = INPUT_TXT.read_text(encoding="utf-8").splitlines()

    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=14)
    pdf.set_left_margin(14)
    pdf.set_right_margin(14)
    pdf.add_font("ArialUnicode", "", str(FONT_PATH))
    pdf.add_page()

    for i, raw in enumerate(lines):
        line = raw.rstrip()
        if not line:
            pdf.ln(2)
            continue

        if i < 3 and (
            line.startswith("ТЕХНИЧЕСКОЕ")
            or "Функция записи тренировок" in line
        ):
            pdf.set_font("ArialUnicode", size=13)
            pdf.multi_cell(0, 7, text=line, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
            pdf.set_font("ArialUnicode", size=10)
            continue

        if SECTION_RE.match(line):
            pdf.ln(1)
            pdf.set_font("ArialUnicode", size=11)
            pdf.multi_cell(0, 6, text=line, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
            pdf.set_font("ArialUnicode", size=10)
            continue

        pdf.multi_cell(0, 5, text=line, new_x=XPos.LMARGIN, new_y=YPos.NEXT)

    OUTPUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    pdf.output(str(OUTPUT_PDF))
    print(f"Wrote {OUTPUT_PDF}")


if __name__ == "__main__":
    main()
