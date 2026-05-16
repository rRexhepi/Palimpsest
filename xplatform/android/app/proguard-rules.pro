# read_pdf_text -> tom_roush.pdfbox -> optional JPEG2000 decoder. We
# don't ship JP2 support, so silence R8 about the missing class instead
# of pulling in another native dep.
-dontwarn com.gemalto.jp2.**
